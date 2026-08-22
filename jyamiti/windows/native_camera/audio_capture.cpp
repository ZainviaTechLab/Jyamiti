// Native WASAPI microphone capture, used by MathPadRecordingService's
// "precise" camera sync method to also give the audio track an exact
// hardware-measured start timestamp -- see camera_capture.cpp for the
// parallel camera-side module and the shared reasoning (reading the real
// system clock at the exact instant the first real sample arrives,
// instead of estimating from when a start() call happens to resolve).
//
// Unlike the camera, WASAPI shared-mode capture does NOT exclusively
// lock the microphone -- confirmed on real hardware, multiple capture
// sessions can read from the same input device concurrently. There's no
// equivalent here to the camera's MF_E_END_OF_STREAM conflict, so this
// module didn't need the same "must fully replace the existing capture
// path" reasoning -- it happens to anyway (this IS the capture path for
// "precise" mode), just for a simpler reason: consistency with the
// camera module, and because generating our own timestamp requires
// owning the capture loop that produces it.
//
// Writes a plain WAV file in whatever format the audio engine's own
// shared-mode mix format actually is -- commonly 32-bit float, 48kHz,
// stereo on modern Windows (confirmed on this machine), NOT necessarily
// the mono/16-bit shape the ffmpeg-path's `record` package was asked
// for. Downstream ffmpeg encode() already explicitly resamples/downmixes
// to whatever the final AAC track needs, so this never has to fight the
// audio engine's native format -- it just needs to be a VALID WAV file,
// which serializing the engine's own WAVEFORMATEX(TENSIBLE) straight
// into the fmt chunk guarantees.
//
// MMCSS priority (see `AvSetMmThreadCharacteristicsW` in Run(), below):
// WASAPI shared-mode capture hands data through a small, fixed-size ring
// buffer -- if this thread doesn't drain it (GetBuffer/ReleaseBuffer)
// often enough, the OLDEST unread audio is silently overwritten with no
// error of any kind. A plain `std::thread` runs at normal priority, so
// under real CPU contention (the camera's H.264 encoder, a background
// segment-seal ffmpeg encode -- both of which this app already runs
// concurrently) the OS scheduler can starve it long enough for that to
// happen -- confirmed as the real cause of a "missing audio in the last
// few seconds" bug found via real-hardware testing (worst right near a
// recording's end, when segment-seal + finalize load tends to peak).
// Registering with MMCSS is the standard fix every real-time audio
// capture application uses for exactly this: it tells the scheduler this
// thread does pro-audio work and must not be starved, independent of
// whatever else is competing for CPU.
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <avrt.h>

#include <atomic>
#include <cstdio>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>
#include <memory>

#pragma comment(lib, "avrt.lib")

#pragma comment(lib, "ole32.lib")

namespace {

long long FileTimeToUnixMicros(const FILETIME& ft) {
    ULARGE_INTEGER u;
    u.LowPart = ft.dwLowDateTime;
    u.HighPart = ft.dwHighDateTime;
    long long ticksSince1601 = static_cast<long long>(u.QuadPart);
    long long unixTicks = ticksSince1601 - 116444736000000000LL;
    return unixTicks / 10;
}

#pragma pack(push, 1)
struct RiffHeader {
    char riffId[4];
    uint32_t riffSize;
    char waveId[4];
};
struct ChunkHeader {
    char id[4];
    uint32_t size;
};
#pragma pack(pop)

class AudioCapture {
public:
    void Start(std::wstring outputPath, bool useRawCapture) {
        worker_ = std::thread([this, outputPath = std::move(outputPath), useRawCapture]() {
            Run(outputPath, useRawCapture);
        });
    }

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

    void Run(const std::wstring& outputPath, bool useRawCapture) {
        HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
            SetError(L"CoInitializeEx failed", hr);
            return;
        }
        bool comInitialized = SUCCEEDED(hr);

        // See the file-level "MMCSS priority" comment above -- this is
        // what actually prevents the capture buffer from silently
        // overflowing under CPU contention from the camera encoder/
        // segment-seal encodes. "Pro Audio" is the highest-priority
        // MMCSS task category, the same one professional real-time audio
        // capture applications register with; a failed registration
        // (returns nullptr -- e.g. a locked-down environment where MMCSS
        // isn't available) is non-fatal, capture just proceeds at normal
        // priority same as before this existed.
        DWORD mmcssTaskIndex = 0;
        HANDLE mmcssHandle = AvSetMmThreadCharacteristicsW(L"Pro Audio", &mmcssTaskIndex);

        IMMDeviceEnumerator* pEnumerator = nullptr;
        IMMDevice* pDevice = nullptr;
        IAudioClient* pAudioClient = nullptr;
        IAudioCaptureClient* pCaptureClient = nullptr;
        WAVEFORMATEX* pwfx = nullptr;
        FILE* pFile = nullptr;

        auto cleanup = [&]() {
            if (pFile) fclose(pFile);
            if (pwfx) CoTaskMemFree(pwfx);
            if (pCaptureClient) pCaptureClient->Release();
            if (pAudioClient) pAudioClient->Release();
            if (pDevice) pDevice->Release();
            if (pEnumerator) pEnumerator->Release();
            if (comInitialized) CoUninitialize();
            if (mmcssHandle) AvRevertMmThreadCharacteristics(mmcssHandle);
        };

        hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
            __uuidof(IMMDeviceEnumerator), (void**)&pEnumerator);
        if (FAILED(hr)) { SetError(L"CoCreateInstance(MMDeviceEnumerator) failed", hr); cleanup(); return; }

        // Same default input device the ffmpeg/`record`-package path
        // already uses (no explicit device is ever selected there
        // either) -- keeps the two capture paths interchangeable from
        // the tutor's point of view.
        hr = pEnumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &pDevice);
        if (FAILED(hr)) { SetError(L"GetDefaultAudioEndpoint failed", hr); cleanup(); return; }

        hr = pDevice->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&pAudioClient);
        if (FAILED(hr)) { SetError(L"Activate(IAudioClient) failed", hr); cleanup(); return; }

        // Optionally request RAW (unprocessed) capture -- by default
        // WASAPI runs the signal through Windows' own microphone-
        // enhancement chain (noise suppression, AGC), which adapts to
        // what it thinks is the "noise floor". A sustained, unvarying
        // tone (a long held vowel) looks exactly like steady-state noise
        // to that algorithm and gets progressively gated out after a
        // moment, while normal speech -- which keeps varying -- never
        // triggers it. Confirmed as the real cause of a "some audio
        // missing, normal speech fine" bug found via real user testing.
        // This is the same protection the ffmpeg/`record`-package path
        // already had via its own `autoGain: false, noiseSuppress:
        // false` options (see start()'s doc comment on that
        // RecordConfig).
        //
        // Tutor-selectable (see `MicEnhancementMode` in
        // mathpad_recording_service.dart) rather than forced -- Windows'
        // enhancements are a genuine net win in a genuinely noisy room
        // for a tutor who doesn't sustain long tones, so this doesn't
        // unconditionally take that away. Requires IAudioClient2;
        // querying for it and setting this is best-effort -- some
        // devices/drivers don't support RAW mode, in which case capture
        // just proceeds through the normal (enhanced) chain regardless
        // of what was requested, rather than failing outright.
        if (useRawCapture) {
            IAudioClient2* pAudioClient2 = nullptr;
            if (SUCCEEDED(pAudioClient->QueryInterface(__uuidof(IAudioClient2), (void**)&pAudioClient2))) {
                AudioClientProperties props = {};
                props.cbSize = sizeof(AudioClientProperties);
                props.bIsOffload = FALSE;
                props.eCategory = AudioCategory_Media;
                props.Options = AUDCLNT_STREAMOPTIONS_RAW;
                pAudioClient2->SetClientProperties(&props);
                pAudioClient2->Release();
            }
        }

        hr = pAudioClient->GetMixFormat(&pwfx);
        if (FAILED(hr)) { SetError(L"GetMixFormat failed", hr); cleanup(); return; }

        // 3 seconds -- a second line of defense alongside the MMCSS
        // registration above: even a thread that IS getting starved
        // occasionally now has a much bigger cushion before the ring
        // buffer actually wraps and starts silently overwriting unread
        // audio.
        const REFERENCE_TIME hnsBufferDuration = 30000000;
        hr = pAudioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, hnsBufferDuration, 0, pwfx, nullptr);
        if (FAILED(hr)) { SetError(L"IAudioClient::Initialize failed", hr); cleanup(); return; }

        hr = pAudioClient->GetService(__uuidof(IAudioCaptureClient), (void**)&pCaptureClient);
        if (FAILED(hr)) { SetError(L"GetService(IAudioCaptureClient) failed", hr); cleanup(); return; }

        const errno_t openErr = _wfopen_s(&pFile, outputPath.c_str(), L"wb");
        if (openErr != 0 || !pFile) { SetError(L"Could not open output WAV file", E_FAIL); cleanup(); return; }

        // Placeholder header -- sizes get patched in once the real total
        // is known, standard streaming-WAV-writer pattern (avoids having
        // to buffer the whole recording in memory just to know its size
        // up front).
        const long riffSizeOffset = sizeof(RiffHeader) - sizeof(uint32_t) - 4; // offset of riffSize field
        RiffHeader riff{{'R', 'I', 'F', 'F'}, 0, {'W', 'A', 'V', 'E'}};
        fwrite(&riff, sizeof(riff), 1, pFile);

        const uint32_t fmtChunkSize = sizeof(WAVEFORMATEX) + pwfx->cbSize;
        ChunkHeader fmtHeader{{'f', 'm', 't', ' '}, fmtChunkSize};
        fwrite(&fmtHeader, sizeof(fmtHeader), 1, pFile);
        fwrite(pwfx, fmtChunkSize, 1, pFile);

        const long dataSizeOffset = ftell(pFile) + 4; // offset of data chunk's size field
        ChunkHeader dataHeader{{'d', 'a', 't', 'a'}, 0};
        fwrite(&dataHeader, sizeof(dataHeader), 1, pFile);

        hr = pAudioClient->Start();
        if (FAILED(hr)) { SetError(L"IAudioClient::Start failed", hr); cleanup(); return; }

        bool firstSeen = false;
        uint32_t totalDataBytes = 0;
        const UINT32 bytesPerFrame = pwfx->nBlockAlign;
        std::vector<BYTE> silenceBuf;

        while (!shouldStop_.load(std::memory_order_relaxed)) {
            UINT32 packetLength = 0;
            hr = pCaptureClient->GetNextPacketSize(&packetLength);
            if (FAILED(hr)) { SetError(L"GetNextPacketSize failed", hr); break; }
            if (packetLength == 0) { Sleep(5); continue; }

            bool packetError = false;
            while (packetLength != 0) {
                BYTE* pData = nullptr;
                UINT32 numFrames = 0;
                DWORD flags = 0;
                hr = pCaptureClient->GetBuffer(&pData, &numFrames, &flags, nullptr, nullptr);
                if (FAILED(hr)) { SetError(L"GetBuffer failed", hr); packetError = true; break; }

                if (!firstSeen && numFrames > 0) {
                    firstSeen = true;
                    FILETIME wallAt;
                    GetSystemTimePreciseAsFileTime(&wallAt);
                    firstFrameUnixMicros_.store(FileTimeToUnixMicros(wallAt),
                        std::memory_order_relaxed);
                    // Release/acquire pair with FirstFrameReady() -- see
                    // the identical comment in camera_capture.cpp.
                    firstFrameReady_.store(true, std::memory_order_release);
                }

                const size_t byteCount = static_cast<size_t>(numFrames) * bytesPerFrame;
                if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
                    // The engine can hand back a "silent" placeholder
                    // packet (typically the very first one, before real
                    // audio has propagated through) -- still genuine
                    // timeline data that must be written, not skipped,
                    // or the file's duration would drift short of the
                    // real elapsed recording time.
                    if (silenceBuf.size() < byteCount) silenceBuf.assign(byteCount, 0);
                    fwrite(silenceBuf.data(), 1, byteCount, pFile);
                } else {
                    fwrite(pData, 1, byteCount, pFile);
                }
                totalDataBytes += static_cast<uint32_t>(byteCount);

                hr = pCaptureClient->ReleaseBuffer(numFrames);
                if (FAILED(hr)) { SetError(L"ReleaseBuffer failed", hr); packetError = true; break; }

                hr = pCaptureClient->GetNextPacketSize(&packetLength);
                if (FAILED(hr)) { SetError(L"GetNextPacketSize failed", hr); packetError = true; break; }
            }
            if (packetError) break;
        }

        pAudioClient->Stop();

        // Patch the two size fields now that the real total is known.
        const uint32_t finalRiffSize = 4 /* "WAVE" */ + sizeof(ChunkHeader) + fmtChunkSize +
            sizeof(ChunkHeader) + totalDataBytes;
        fseek(pFile, riffSizeOffset, SEEK_SET);
        fwrite(&finalRiffSize, sizeof(finalRiffSize), 1, pFile);
        fseek(pFile, dataSizeOffset, SEEK_SET);
        fwrite(&totalDataBytes, sizeof(totalDataBytes), 1, pFile);

        finalizedOk_.store(true, std::memory_order_relaxed);
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

std::mutex g_audioHandlesMutex;
std::unordered_map<int64_t, std::unique_ptr<AudioCapture>> g_audioHandles;
std::atomic<int64_t> g_nextAudioHandle{1};

}  // namespace

extern "C" {

__declspec(dllexport) int64_t jyamiti_audio_start(const wchar_t* outputPath, int32_t useRawCapture) {
    if (!outputPath) return 0;
    auto capture = std::make_unique<AudioCapture>();
    capture->Start(outputPath, useRawCapture != 0);

    int64_t handle = g_nextAudioHandle.fetch_add(1, std::memory_order_relaxed);
    std::lock_guard<std::mutex> lock(g_audioHandlesMutex);
    g_audioHandles[handle] = std::move(capture);
    return handle;
}

__declspec(dllexport) int32_t jyamiti_audio_is_first_frame_ready(int64_t handle) {
    std::lock_guard<std::mutex> lock(g_audioHandlesMutex);
    auto it = g_audioHandles.find(handle);
    if (it == g_audioHandles.end()) return 0;
    return it->second->FirstFrameReady() ? 1 : 0;
}

__declspec(dllexport) int64_t jyamiti_audio_first_frame_unix_micros(int64_t handle) {
    std::lock_guard<std::mutex> lock(g_audioHandlesMutex);
    auto it = g_audioHandles.find(handle);
    if (it == g_audioHandles.end()) return 0;
    return it->second->FirstFrameUnixMicros();
}

__declspec(dllexport) int32_t jyamiti_audio_stop(int64_t handle) {
    AudioCapture* capture = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_audioHandlesMutex);
        auto it = g_audioHandles.find(handle);
        if (it == g_audioHandles.end()) return 0;
        capture = it->second.get();
    }
    return capture->Stop() ? 1 : 0;
}

__declspec(dllexport) int32_t jyamiti_audio_last_error(int64_t handle, wchar_t* outBuffer,
                                                         int32_t outBufferChars) {
    if (!outBuffer || outBufferChars <= 0) return 0;
    outBuffer[0] = L'\0';
    std::wstring message;
    {
        std::lock_guard<std::mutex> lock(g_audioHandlesMutex);
        auto it = g_audioHandles.find(handle);
        if (it == g_audioHandles.end()) return 0;
        message = it->second->LastError();
    }
    wcsncpy_s(outBuffer, outBufferChars, message.c_str(), _TRUNCATE);
    return 1;
}

__declspec(dllexport) void jyamiti_audio_destroy(int64_t handle) {
    std::lock_guard<std::mutex> lock(g_audioHandlesMutex);
    g_audioHandles.erase(handle);
}

}  // extern "C"
