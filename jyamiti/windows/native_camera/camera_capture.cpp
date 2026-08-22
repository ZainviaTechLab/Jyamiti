// Native Media Foundation webcam capture+encode, used by
// MathPadRecordingService's "precise" camera sync method as an
// alternative to spawning ffmpeg for the camera stream.
//
// WHY THIS EXISTS: ffmpeg (via DirectShow) can only tell us the camera
// started "close to" a given moment -- the best we can measure from
// outside the process is when its stderr happens to print a status line,
// which is bounded by how often it chooses to print (see
// MathPadRecordingService's `-stats_period` handling). Media Foundation's
// IMFSourceReader, in contrast, hands back each frame the instant it's
// actually delivered by the driver -- reading the real system clock
// (GetSystemTimePreciseAsFileTime) right then gives a genuinely exact,
// sub-millisecond timestamp for when the very first frame was captured.
//
// Testing on real hardware found that Media Foundation and ffmpeg's
// DirectShow capture CANNOT reliably share the same physical camera at
// once (the second opener gets MF_E_END_OF_STREAM with no data) -- so
// this module does the FULL capture+encode itself (SourceReader -> H.264
// encoder MFT, auto-negotiated -> SinkWriter -> MP4), not just a
// timestamp handshake handed off to ffmpeg.
//
// The output file's own frame timestamps stay small and 0-based, exactly
// like a normal recording (see `relTime` below) -- the real wall-clock
// anchor for the first frame is reported out-of-band via
// jyamiti_camera_first_frame_unix_micros(), not embedded in the file
// itself. Embedding real wall-clock values as frame PTS was tried and
// found to corrupt encoding (non-monotonic-timestamp errors, unplayable
// output) -- see MathPadRecordingService's commit history for that
// finding.
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>

#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <memory>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "mf.lib")
#pragma comment(lib, "ole32.lib")

namespace {

long long FileTimeToUnixMicros(const FILETIME& ft) {
    ULARGE_INTEGER u;
    u.LowPart = ft.dwLowDateTime;
    u.HighPart = ft.dwHighDateTime;
    long long ticksSince1601 = static_cast<long long>(u.QuadPart);
    // FILETIME: 100ns ticks since 1601-01-01. Unix epoch is 1970-01-01,
    // 11644473600 seconds (in 100ns ticks) later.
    long long unixTicks = ticksSince1601 - 116444736000000000LL;
    return unixTicks / 10;
}

class CameraCapture {
public:
    // Runs entirely on `worker_` -- constructed on the caller's thread,
    // everything Media Foundation-related happens on the worker so a slow
    // device open/negotiate can never block the caller (mirrors the
    // "camera trouble never blocks the recording" philosophy used
    // throughout MathPadRecordingService).
    void Start(std::wstring deviceName, std::wstring outputPath) {
        worker_ = std::thread([this, deviceName = std::move(deviceName),
                                outputPath = std::move(outputPath)]() {
            Run(deviceName, outputPath);
        });
    }

    // Signals the worker to stop after its current frame, finalizes the
    // output file, and blocks until the worker thread has fully exited.
    // Safe to call more than once.
    bool Stop() {
        shouldStop_.store(true, std::memory_order_relaxed);
        if (worker_.joinable()) worker_.join();
        return finalizedOk_.load(std::memory_order_relaxed);
    }

    bool FirstFrameReady() const {
        return firstFrameReady_.load(std::memory_order_acquire);
    }

    long long FirstFrameUnixMicros() const {
        return firstFrameUnixMicros_.load(std::memory_order_acquire);
    }

    std::wstring LastError() {
        std::lock_guard<std::mutex> lock(errorMutex_);
        return lastError_;
    }

private:
    void SetError(const wchar_t* what, HRESULT hr) {
        wchar_t buf[256];
        swprintf_s(buf, L"%s (hr=0x%08lx)", what, hr);
        std::lock_guard<std::mutex> lock(errorMutex_);
        lastError_ = buf;
    }

    void Run(const std::wstring& deviceName, const std::wstring& outputPath) {
        HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        // RPC_E_CHANGED_MODE just means this thread's COM apartment was
        // already initialized differently by something else -- harmless
        // for our purposes here, everything else is fatal.
        if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
            SetError(L"CoInitializeEx failed", hr);
            return;
        }
        bool comInitialized = SUCCEEDED(hr);

        bool mfStarted = false;
        IMFAttributes* pAttributes = nullptr;
        IMFActivate** ppDevices = nullptr;
        UINT32 deviceCount = 0;
        IMFMediaSource* pSource = nullptr;
        IMFSourceReader* pReader = nullptr;
        IMFMediaType* pTypeNV12 = nullptr;
        IMFMediaType* pTypeOut = nullptr;
        IMFMediaType* pTypeIn = nullptr;
        IMFSinkWriter* pSinkWriter = nullptr;
        DWORD sinkStreamIndex = 0;

        auto cleanup = [&]() {
            if (pTypeIn) pTypeIn->Release();
            if (pTypeOut) pTypeOut->Release();
            if (pSinkWriter) pSinkWriter->Release();
            if (pTypeNV12) pTypeNV12->Release();
            if (pReader) pReader->Release();
            if (pSource) { pSource->Shutdown(); pSource->Release(); }
            if (ppDevices) {
                for (UINT32 i = 0; i < deviceCount; i++) {
                    if (ppDevices[i]) ppDevices[i]->Release();
                }
                CoTaskMemFree(ppDevices);
            }
            if (pAttributes) pAttributes->Release();
            if (mfStarted) MFShutdown();
            if (comInitialized) CoUninitialize();
        };

        hr = MFStartup(MF_VERSION);
        if (FAILED(hr)) { SetError(L"MFStartup failed", hr); cleanup(); return; }
        mfStarted = true;

        hr = MFCreateAttributes(&pAttributes, 1);
        if (SUCCEEDED(hr)) {
            hr = pAttributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
        }
        if (FAILED(hr)) { SetError(L"MFCreateAttributes failed", hr); cleanup(); return; }

        hr = MFEnumDeviceSources(pAttributes, &ppDevices, &deviceCount);
        if (FAILED(hr)) { SetError(L"MFEnumDeviceSources failed", hr); cleanup(); return; }

        IMFActivate* pChosen = nullptr;
        for (UINT32 i = 0; i < deviceCount; i++) {
            wchar_t* friendlyName = nullptr;
            UINT32 len = 0;
            if (SUCCEEDED(ppDevices[i]->GetAllocatedString(
                    MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &friendlyName, &len))) {
                if (deviceName == friendlyName) pChosen = ppDevices[i];
                CoTaskMemFree(friendlyName);
            }
            if (pChosen) break;
        }
        if (!pChosen) {
            // Fall back to the first device rather than failing outright --
            // matches how the ffmpeg path behaves when a name lookup comes
            // back ambiguous; still far better than no camera at all.
            if (deviceCount > 0) pChosen = ppDevices[0];
        }
        if (!pChosen) { SetError(L"No camera device found", E_FAIL); cleanup(); return; }

        hr = pChosen->ActivateObject(IID_PPV_ARGS(&pSource));
        if (FAILED(hr)) { SetError(L"ActivateObject failed", hr); cleanup(); return; }

        hr = MFCreateSourceReaderFromMediaSource(pSource, nullptr, &pReader);
        if (FAILED(hr)) { SetError(L"MFCreateSourceReaderFromMediaSource failed", hr); cleanup(); return; }

        hr = MFCreateMediaType(&pTypeNV12);
        if (SUCCEEDED(hr)) hr = pTypeNV12->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        if (SUCCEEDED(hr)) hr = pTypeNV12->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
        if (SUCCEEDED(hr)) {
            hr = pReader->SetCurrentMediaType(
                (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, pTypeNV12);
        }
        if (FAILED(hr)) { SetError(L"Negotiating NV12 output failed", hr); cleanup(); return; }

        UINT32 frameW = 1280, frameH = 720, fpsNum = 30, fpsDen = 1;
        {
            IMFMediaType* pActual = nullptr;
            if (SUCCEEDED(pReader->GetCurrentMediaType(
                    (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &pActual))) {
                MFGetAttributeSize(pActual, MF_MT_FRAME_SIZE, &frameW, &frameH);
                MFGetAttributeRatio(pActual, MF_MT_FRAME_RATE, &fpsNum, &fpsDen);
                pActual->Release();
            }
        }
        if (fpsNum == 0) { fpsNum = 30; fpsDen = 1; }

        hr = pReader->SetStreamSelection((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE);
        if (FAILED(hr)) { SetError(L"SetStreamSelection failed", hr); cleanup(); return; }

        hr = MFCreateSinkWriterFromURL(outputPath.c_str(), nullptr, nullptr, &pSinkWriter);
        if (FAILED(hr)) { SetError(L"MFCreateSinkWriterFromURL failed", hr); cleanup(); return; }

        hr = MFCreateMediaType(&pTypeOut);
        if (SUCCEEDED(hr)) hr = pTypeOut->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        if (SUCCEEDED(hr)) hr = pTypeOut->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
        if (SUCCEEDED(hr)) hr = pTypeOut->SetUINT32(MF_MT_AVG_BITRATE, 6000000);
        if (SUCCEEDED(hr)) hr = pTypeOut->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
        if (SUCCEEDED(hr)) hr = MFSetAttributeSize(pTypeOut, MF_MT_FRAME_SIZE, frameW, frameH);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(pTypeOut, MF_MT_FRAME_RATE, fpsNum, fpsDen);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(pTypeOut, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
        if (SUCCEEDED(hr)) hr = pSinkWriter->AddStream(pTypeOut, &sinkStreamIndex);
        if (FAILED(hr)) { SetError(L"Configuring H.264 output failed", hr); cleanup(); return; }

        hr = MFCreateMediaType(&pTypeIn);
        if (SUCCEEDED(hr)) hr = pTypeIn->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        if (SUCCEEDED(hr)) hr = pTypeIn->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
        if (SUCCEEDED(hr)) hr = pTypeIn->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
        if (SUCCEEDED(hr)) hr = MFSetAttributeSize(pTypeIn, MF_MT_FRAME_SIZE, frameW, frameH);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(pTypeIn, MF_MT_FRAME_RATE, fpsNum, fpsDen);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(pTypeIn, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
        // This is what actually triggers the SinkWriter to find and spin
        // up an H.264 encoder MFT matching pTypeIn -> pTypeOut (hardware
        // encoder if the system has one registered, otherwise Windows'
        // built-in software H.264 encoder).
        if (SUCCEEDED(hr)) hr = pSinkWriter->SetInputMediaType(sinkStreamIndex, pTypeIn, nullptr);
        if (FAILED(hr)) { SetError(L"Negotiating H.264 encoder failed", hr); cleanup(); return; }

        hr = pSinkWriter->BeginWriting();
        if (FAILED(hr)) { SetError(L"BeginWriting failed", hr); cleanup(); return; }

        bool firstFrameSeen = false;
        LONGLONG firstSampleTime = 0;
        while (!shouldStop_.load(std::memory_order_relaxed)) {
            DWORD streamIndex = 0, flags = 0;
            LONGLONG sampleTime = 0;
            IMFSample* pSample = nullptr;
            hr = pReader->ReadSample(
                (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0,
                &streamIndex, &flags, &sampleTime, &pSample);

            if (FAILED(hr)) { SetError(L"ReadSample failed", hr); break; }
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
            if (!pSample) continue; // format-change or similar notify-only event

            if (!firstFrameSeen) {
                FILETIME wallAt;
                GetSystemTimePreciseAsFileTime(&wallAt);
                firstFrameUnixMicros_.store(FileTimeToUnixMicros(wallAt),
                    std::memory_order_relaxed);
                firstSampleTime = sampleTime;
                firstFrameSeen = true;
                // Publish the timestamp before the readiness flag so a
                // caller that observes FirstFrameReady()==true is
                // guaranteed to see a valid timestamp (release/acquire
                // pair with FirstFrameReady()).
                firstFrameReady_.store(true, std::memory_order_release);
            }

            // Keep the file's own timestamps small and 0-based -- see the
            // file-level comment on why the real wall-clock anchor is
            // reported out-of-band instead of embedded here.
            pSample->SetSampleTime(sampleTime - firstSampleTime);

            hr = pSinkWriter->WriteSample(sinkStreamIndex, pSample);
            pSample->Release();
            if (FAILED(hr)) { SetError(L"WriteSample failed", hr); break; }
        }

        hr = pSinkWriter->Finalize();
        finalizedOk_.store(SUCCEEDED(hr), std::memory_order_relaxed);
        if (FAILED(hr)) SetError(L"Finalize failed", hr);

        cleanup();
    }

    std::thread worker_;
    std::atomic<bool> shouldStop_{false};
    std::atomic<bool> firstFrameReady_{false};
    std::atomic<long long> firstFrameUnixMicros_{0};
    std::atomic<bool> finalizedOk_{false};
    std::mutex errorMutex_;
    std::wstring lastError_;
};

// Handle table -- simple opaque-int64-handle scheme, mirroring how the
// rest of this app already deals with FFI (see the Dart-side Win32 Job
// Object code in MathPadRecordingService for the equivalent pattern on
// the Dart/win32 package side).
std::mutex g_handlesMutex;
std::unordered_map<int64_t, std::unique_ptr<CameraCapture>> g_handles;
std::atomic<int64_t> g_nextHandle{1};

}  // namespace

extern "C" {

__declspec(dllexport) int64_t jyamiti_camera_start(const wchar_t* deviceName,
                                                     const wchar_t* outputPath) {
    if (!deviceName || !outputPath) return 0;
    auto capture = std::make_unique<CameraCapture>();
    capture->Start(deviceName, outputPath);

    int64_t handle = g_nextHandle.fetch_add(1, std::memory_order_relaxed);
    std::lock_guard<std::mutex> lock(g_handlesMutex);
    g_handles[handle] = std::move(capture);
    return handle;
}

__declspec(dllexport) int32_t jyamiti_camera_is_first_frame_ready(int64_t handle) {
    std::lock_guard<std::mutex> lock(g_handlesMutex);
    auto it = g_handles.find(handle);
    if (it == g_handles.end()) return 0;
    return it->second->FirstFrameReady() ? 1 : 0;
}

__declspec(dllexport) int64_t jyamiti_camera_first_frame_unix_micros(int64_t handle) {
    std::lock_guard<std::mutex> lock(g_handlesMutex);
    auto it = g_handles.find(handle);
    if (it == g_handles.end()) return 0;
    return it->second->FirstFrameUnixMicros();
}

__declspec(dllexport) int32_t jyamiti_camera_stop(int64_t handle) {
    CameraCapture* capture = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_handlesMutex);
        auto it = g_handles.find(handle);
        if (it == g_handles.end()) return 0;
        capture = it->second.get();
    }
    // Stop() joins the worker thread -- deliberately done without holding
    // g_handlesMutex, so a concurrent status query on another handle
    // isn't blocked for the whole encode-finalize duration.
    return capture->Stop() ? 1 : 0;
}

__declspec(dllexport) int32_t jyamiti_camera_last_error(int64_t handle, wchar_t* outBuffer,
                                                          int32_t outBufferChars) {
    if (!outBuffer || outBufferChars <= 0) return 0;
    outBuffer[0] = L'\0';
    std::wstring message;
    {
        std::lock_guard<std::mutex> lock(g_handlesMutex);
        auto it = g_handles.find(handle);
        if (it == g_handles.end()) return 0;
        message = it->second->LastError();
    }
    wcsncpy_s(outBuffer, outBufferChars, message.c_str(), _TRUNCATE);
    return 1;
}

__declspec(dllexport) void jyamiti_camera_destroy(int64_t handle) {
    std::lock_guard<std::mutex> lock(g_handlesMutex);
    g_handles.erase(handle);
}

}  // extern "C"
