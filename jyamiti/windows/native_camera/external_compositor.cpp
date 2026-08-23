// Native "external compositor" -- captures Math Pad's own window content
// via the Windows Graphics Capture API (the same mechanism OBS's modern
// window-capture source uses -- taps into content DWM has ALREADY
// composited for display, no extra rendering work asked of the app
// itself), optionally composites a live camera feed on top via Direct2D,
// and encodes the result in real time via a piped ffmpeg process.
//
// WHY THIS EXISTS: CameraEncodeMode.onCanvas (Flutter-side live camera
// compositing) and RecordingPipelineMode.continuousStream (Flutter-side
// raw-frame piping) both do real, valuable work, but both still run on
// Flutter's own UI/raster thread -- confirmed via real testing to cause
// drawing lag/stutter under `onCanvas`, since a live camera texture
// invalidates the capture area's RepaintBoundary at the camera's own
// frame rate, forcing more frequent expensive toImage()/GPU-readback
// calls than a static whiteboard would ever need, all competing with
// the tutor's own pointer/gesture events on the same thread. This module
// is the genuine fix: capture, composite, AND encode all happen in this
// separate native process/thread, entirely outside Flutter's rendering
// pipeline -- drawing stays exactly as smooth as if no recording (of any
// kind) were happening at all.
//
// SCOPE NOTE: captures the app's FULL top-level window (WGC's natural
// granularity), not precisely cropped to just the canvas capture area
// the other CameraEncodeMode/RecordingPipelineMode options use -- a
// deliberate simplification for this first version (avoids needing to
// track/pass the capture area's exact position within the window, which
// would also need updating live if the window is resized or the
// surrounding UI changes). Documented on the Dart-side enum value too.
#include <windows.h>
#include <d3d11.h>
#include <d2d1_1.h>
#include <dxgi1_2.h>
#include <wrl/client.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <Windows.Graphics.Capture.Interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <avrt.h>

#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>
#include <memory>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "windowsapp.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "mf.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "avrt.lib")

using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::DirectX;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;
using Microsoft::WRL::ComPtr;

namespace {

// Finds the current process's own visible top-level window -- this app
// has exactly one, created by the Flutter engine's window controller.
// Avoids needing an HWND passed in from Dart at all (Flutter Windows
// doesn't straightforwardly expose its own native HWND to Dart code).
HWND FindOwnWindow() {
    DWORD pid = GetCurrentProcessId();
    HWND result = nullptr;
    HWND h = nullptr;
    do {
        h = h ? GetWindow(h, GW_HWNDNEXT) : GetTopWindow(nullptr);
        if (!h) break;
        DWORD windowPid = 0;
        GetWindowThreadProcessId(h, &windowPid);
        if (windowPid == pid && IsWindowVisible(h)) {
            result = h;
            break;
        }
    } while (h);
    return result;
}

// Same convention as the rest of this app's native code -- ffmpeg.exe is
// installed next to the app's own exe (see windows/CMakeLists.txt).
std::wstring ResolveFfmpegPath() {
    wchar_t exePath[MAX_PATH];
    GetModuleFileNameW(nullptr, exePath, MAX_PATH);
    std::wstring path(exePath);
    size_t slash = path.find_last_of(L"\\/");
    std::wstring dir = slash != std::wstring::npos ? path.substr(0, slash) : L".";
    return dir + L"\\ffmpeg.exe";
}

IDirect3DDevice CreateWinRTDevice(ComPtr<ID3D11Device>& d3dDevice) {
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    D3D_FEATURE_LEVEL featureLevel;
    ComPtr<ID3D11DeviceContext> context;
    HRESULT hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
        nullptr, 0, D3D11_SDK_VERSION, &d3dDevice, &featureLevel, &context);
    if (FAILED(hr)) return nullptr;
    ComPtr<IDXGIDevice> dxgiDevice;
    d3dDevice.As(&dxgiDevice);
    com_ptr<::IInspectable> inspectable;
    hr = CreateDirect3D11DeviceFromDXGIDevice(
        dxgiDevice.Get(), reinterpret_cast<IInspectable**>(put_abi(inspectable)));
    if (FAILED(hr)) return nullptr;
    return inspectable.as<IDirect3DDevice>();
}

class ExternalCompositor {
public:
    void Start(std::wstring cameraDeviceName, std::wstring outputPath, int fps) {
        worker_ = std::thread([this, cameraDeviceName = std::move(cameraDeviceName),
                                outputPath = std::move(outputPath), fps]() {
            Run(cameraDeviceName, outputPath, fps);
        });
    }

    bool Stop() {
        shouldStop_.store(true, std::memory_order_relaxed);
        if (worker_.joinable()) worker_.join();
        return finalizedOk_.load(std::memory_order_relaxed);
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
    void SetError(const wchar_t* what) {
        std::lock_guard<std::mutex> lock(errorMutex_);
        lastError_ = what;
    }

    void Run(const std::wstring& cameraDeviceName, const std::wstring& outputPath, int fps) {
        init_apartment(apartment_type::single_threaded);

        // Real-time priority for this thread -- same reasoning as
        // audio_capture.cpp's identical use of this: capture+composite+
        // encode all happening live, in real time, on this one thread
        // must not get starved by whatever else the system is doing.
        DWORD mmcssTaskIndex = 0;
        HANDLE mmcssHandle = AvSetMmThreadCharacteristicsW(L"Pro Audio", &mmcssTaskIndex);

        HWND targetWindow = FindOwnWindow();
        if (!targetWindow) { SetError(L"Could not find the app's own window"); return; }

        ComPtr<ID3D11Device> d3dDevice;
        IDirect3DDevice winrtDevice = CreateWinRTDevice(d3dDevice);
        if (!winrtDevice) { SetError(L"D3D11/WinRT device creation failed"); return; }
        ComPtr<ID3D11DeviceContext> context;
        d3dDevice->GetImmediateContext(&context);

        ComPtr<ID2D1Factory1> d2dFactory;
        HRESULT hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, IID_PPV_ARGS(&d2dFactory));
        if (FAILED(hr)) { SetError(L"D2D1CreateFactory failed", hr); return; }
        ComPtr<IDXGIDevice> dxgiDevice;
        d3dDevice.As(&dxgiDevice);
        ComPtr<ID2D1Device> d2dDevice;
        hr = d2dFactory->CreateDevice(dxgiDevice.Get(), &d2dDevice);
        if (FAILED(hr)) { SetError(L"D2D CreateDevice failed", hr); return; }
        ComPtr<ID2D1DeviceContext> d2dContext;
        hr = d2dDevice->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &d2dContext);
        if (FAILED(hr)) { SetError(L"D2D CreateDeviceContext failed", hr); return; }

        GraphicsCaptureItem item{ nullptr };
        try {
            auto interopFactory = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
            hr = interopFactory->CreateForWindow(targetWindow, guid_of<GraphicsCaptureItem>(), put_abi(item));
        } catch (...) { hr = E_FAIL; }
        if (FAILED(hr) || !item) { SetError(L"CreateForWindow failed", hr); return; }

        UINT32 width = (std::max)(2, ((int)item.Size().Width / 2) * 2);
        UINT32 height = (std::max)(2, ((int)item.Size().Height / 2) * 2);

        Direct3D11CaptureFramePool framePool{ nullptr };
        GraphicsCaptureSession session{ nullptr };
        try {
            framePool = Direct3D11CaptureFramePool::CreateFreeThreaded(
                winrtDevice, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, item.Size());
            session = framePool.CreateCaptureSession(item);
        } catch (...) { SetError(L"Creating capture session failed"); return; }

        // Camera is entirely best-effort -- a failure here only means no
        // camera box gets composited in, never that the recording fails.
        // Same "camera trouble costs the camera, never the recording"
        // philosophy as everywhere else camera work happens in this app.
        bool haveCamera = false;
        IMFAttributes* pCamDeviceAttrs = nullptr;
        IMFActivate** ppCamDevices = nullptr;
        UINT32 camDeviceCount = 0;
        IMFMediaSource* pCamSource = nullptr;
        IMFSourceReader* pCamReader = nullptr;
        UINT32 camW = 0, camH = 0;
        std::vector<BYTE> camBuf;
        bool haveCamFrame = false;

        if (!cameraDeviceName.empty()) {
            MFStartup(MF_VERSION);
            HRESULT camHr = MFCreateAttributes(&pCamDeviceAttrs, 1);
            if (SUCCEEDED(camHr)) {
                camHr = pCamDeviceAttrs->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                    MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
            }
            if (SUCCEEDED(camHr)) camHr = MFEnumDeviceSources(pCamDeviceAttrs, &ppCamDevices, &camDeviceCount);
            IMFActivate* chosen = nullptr;
            if (SUCCEEDED(camHr)) {
                for (UINT32 i = 0; i < camDeviceCount; i++) {
                    wchar_t* name = nullptr;
                    UINT32 len = 0;
                    if (SUCCEEDED(ppCamDevices[i]->GetAllocatedString(
                            MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &name, &len))) {
                        if (cameraDeviceName == name) chosen = ppCamDevices[i];
                        CoTaskMemFree(name);
                    }
                    if (chosen) break;
                }
                if (!chosen && camDeviceCount > 0) chosen = ppCamDevices[0];
            }
            if (chosen) {
                camHr = chosen->ActivateObject(IID_PPV_ARGS(&pCamSource));
                if (SUCCEEDED(camHr)) {
                    IMFAttributes* readerAttrs = nullptr;
                    MFCreateAttributes(&readerAttrs, 1);
                    // Enables the fuller Video Processor MFT for format
                    // conversion -- required to get RGB32 out of a
                    // camera whose native format is something else
                    // (NV12/MJPG/etc), confirmed via direct testing (the
                    // plain decoder-only path fails with
                    // MF_E_INVALIDMEDIATYPE on real hardware).
                    readerAttrs->SetUINT32(MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE);
                    camHr = MFCreateSourceReaderFromMediaSource(pCamSource, readerAttrs, &pCamReader);
                    if (readerAttrs) readerAttrs->Release();
                }
                if (SUCCEEDED(camHr)) {
                    IMFMediaType* pType = nullptr;
                    MFCreateMediaType(&pType);
                    pType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
                    pType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
                    camHr = pCamReader->SetCurrentMediaType((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, pType);
                    if (pType) pType->Release();
                }
                if (SUCCEEDED(camHr)) {
                    pCamReader->SetStreamSelection((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE);
                    IMFMediaType* pActual = nullptr;
                    if (SUCCEEDED(pCamReader->GetCurrentMediaType(
                            (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &pActual))) {
                        MFGetAttributeSize(pActual, MF_MT_FRAME_SIZE, &camW, &camH);
                        pActual->Release();
                    }
                    if (camW > 0 && camH > 0) {
                        camBuf.resize((size_t)camW * camH * 4);
                        haveCamera = true;
                    }
                }
            }
        }

        // Output render target (D2D bitmap backed by a D3D texture) plus
        // a CPU-readable staging copy for feeding ffmpeg's stdin.
        D3D11_TEXTURE2D_DESC rtDesc = {};
        rtDesc.Width = width; rtDesc.Height = height; rtDesc.MipLevels = 1; rtDesc.ArraySize = 1;
        rtDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; rtDesc.SampleDesc.Count = 1;
        rtDesc.Usage = D3D11_USAGE_DEFAULT;
        rtDesc.BindFlags = D3D11_BIND_RENDER_TARGET;
        ComPtr<ID3D11Texture2D> outputTex;
        hr = d3dDevice->CreateTexture2D(&rtDesc, nullptr, &outputTex);
        if (FAILED(hr)) { SetError(L"CreateTexture2D output failed", hr); return; }
        ComPtr<IDXGISurface> outputSurface;
        outputTex.As(&outputSurface);
        D2D1_BITMAP_PROPERTIES1 bp = D2D1::BitmapProperties1(
            D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE));
        ComPtr<ID2D1Bitmap1> outputBitmap;
        hr = d2dContext->CreateBitmapFromDxgiSurface(outputSurface.Get(), &bp, &outputBitmap);
        if (FAILED(hr)) { SetError(L"CreateBitmapFromDxgiSurface output failed", hr); return; }

        D3D11_TEXTURE2D_DESC stagingDesc = rtDesc;
        stagingDesc.Usage = D3D11_USAGE_STAGING;
        stagingDesc.BindFlags = 0;
        stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        ComPtr<ID3D11Texture2D> staging;
        d3dDevice->CreateTexture2D(&stagingDesc, nullptr, &staging);

        ComPtr<ID2D1SolidColorBrush> whiteBrush;
        d2dContext->CreateSolidColorBrush(D2D1::ColorF(1, 1, 1, 0.9f), &whiteBrush);

        // Spawn ffmpeg reading raw BGRA frames from our stdin.
        SECURITY_ATTRIBUTES sa = { sizeof(sa), nullptr, TRUE };
        HANDLE readPipe = nullptr, writePipe = nullptr;
        if (!CreatePipe(&readPipe, &writePipe, &sa, 0)) { SetError(L"CreatePipe failed"); return; }
        SetHandleInformation(writePipe, HANDLE_FLAG_INHERIT, 0);

        std::wstring ffmpegPath = ResolveFfmpegPath();
        wchar_t cmdLine[2048];
        swprintf_s(cmdLine,
            L"\"%s\" -y -f rawvideo -pixel_format bgra -video_size %ux%u -framerate %d -i pipe:0 "
            L"-c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 20 -bf 0 \"%s\"",
            ffmpegPath.c_str(), width, height, fps, outputPath.c_str());

        STARTUPINFOW si = { sizeof(si) };
        si.dwFlags = STARTF_USESTDHANDLES;
        si.hStdInput = readPipe;
        si.hStdOutput = nullptr;
        si.hStdError = nullptr;
        PROCESS_INFORMATION pi = {};
        BOOL spawned = CreateProcessW(nullptr, cmdLine, nullptr, nullptr, TRUE,
            CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);
        CloseHandle(readPipe);
        if (!spawned) { SetError(L"Failed to spawn ffmpeg"); CloseHandle(writePipe); return; }
        // Same "Windows Job Object" protection every other ffmpeg process
        // this app spawns gets (see mathpad_recording_service.dart's own
        // copy of this for the Dart-side processes) -- this one is spawned
        // entirely natively, so it needs its own, independent copy here
        // rather than being able to reuse the Dart-side FFI version.
        // Without this, a hard-kill of jyamiti.exe (Task Manager "End
        // Task", a crash) would leave this ffmpeg process running as an
        // orphan.
        HANDLE job = CreateJobObjectW(nullptr, nullptr);
        if (job) {
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
            limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits));
            AssignProcessToJobObject(job, pi.hProcess);
            // Deliberately never closed/leaked for the lifetime of this
            // process -- the job's kill-on-close semantics only fire when
            // ITS last handle closes, which must not happen before
            // jyamiti.exe itself exits.
        }

        try {
            session.StartCapture();
        } catch (...) { SetError(L"StartCapture failed"); }

        const DWORD frameIntervalMs = (DWORD)(1000 / (std::max)(1, fps));
        while (!shouldStop_.load(std::memory_order_relaxed)) {
            MSG msg;
            while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }

            if (haveCamera) {
                DWORD streamIndex = 0, flags = 0;
                LONGLONG ts = 0;
                IMFSample* sample = nullptr;
                if (SUCCEEDED(pCamReader->ReadSample(
                        (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &streamIndex, &flags, &ts, &sample)) &&
                    sample) {
                    IMFMediaBuffer* buf = nullptr;
                    sample->ConvertToContiguousBuffer(&buf);
                    if (buf) {
                        BYTE* data = nullptr;
                        DWORD len = 0;
                        if (SUCCEEDED(buf->Lock(&data, nullptr, &len)) && len >= camBuf.size()) {
                            memcpy(camBuf.data(), data, camBuf.size());
                            haveCamFrame = true;
                        }
                        buf->Unlock();
                        buf->Release();
                    }
                    sample->Release();
                }
            }

            auto frame = framePool.TryGetNextFrame();
            if (frame) {
                auto surface = frame.Surface();
                ComPtr<ID3D11Texture2D> tex;
                try {
                    auto access = surface.as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
                    access->GetInterface(IID_PPV_ARGS(&tex));
                } catch (...) {}
                if (tex) {
                    ComPtr<IDXGISurface> winSurface;
                    tex.As(&winSurface);
                    D2D1_BITMAP_PROPERTIES1 wbp = D2D1::BitmapProperties1(
                        D2D1_BITMAP_OPTIONS_NONE,
                        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE));
                    ComPtr<ID2D1Bitmap1> winBitmap;
                    if (SUCCEEDED(d2dContext->CreateBitmapFromDxgiSurface(winSurface.Get(), &wbp, &winBitmap))) {
                        d2dContext->SetTarget(outputBitmap.Get());
                        d2dContext->BeginDraw();
                        d2dContext->Clear(D2D1::ColorF(0, 0, 0));
                        d2dContext->DrawBitmap(winBitmap.Get(), D2D1::RectF(0, 0, (float)width, (float)height));

                        if (haveCamFrame) {
                            D2D1_BITMAP_PROPERTIES camProps = D2D1::BitmapProperties(
                                D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE));
                            ComPtr<ID2D1Bitmap> camBitmap;
                            d2dContext->CreateBitmap(D2D1::SizeU(camW, camH), camBuf.data(),
                                camW * 4, camProps, &camBitmap);
                            if (camBitmap) {
                                // Matches the exact PIP spec every other
                                // camera-overlay path in this app uses --
                                // crop=ih:ih, scale=240:240, white
                                // border, top-right 24px inset.
                                float cropSize = (float)(std::min)(camW, camH);
                                float cropX = (camW - cropSize) / 2.0f;
                                D2D1_RECT_F srcRect = D2D1::RectF(cropX, 0, cropX + cropSize, cropSize);
                                float boxSize = 240.0f, inset = 24.0f;
                                D2D1_RECT_F destRect = D2D1::RectF(
                                    width - inset - boxSize, inset, width - inset, inset + boxSize);
                                d2dContext->DrawBitmap(camBitmap.Get(), destRect, 1.0f,
                                    D2D1_INTERPOLATION_MODE_LINEAR, srcRect);
                                d2dContext->DrawRectangle(destRect, whiteBrush.Get(), 4.0f);
                            }
                        }
                        d2dContext->EndDraw();
                    }
                }
            }

            context->CopyResource(staging.Get(), outputTex.Get());
            D3D11_MAPPED_SUBRESOURCE mapped;
            if (SUCCEEDED(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped))) {
                bool writeOk = true;
                for (UINT y = 0; y < height && writeOk; y++) {
                    BYTE* row = (BYTE*)mapped.pData + (size_t)y * mapped.RowPitch;
                    DWORD written = 0;
                    if (!WriteFile(writePipe, row, width * 4, &written, nullptr)) writeOk = false;
                }
                context->Unmap(staging.Get(), 0);
                if (!writeOk) {
                    SetError(L"Writing to the encoder's pipe failed -- it may have exited");
                    break;
                }
            }

            Sleep(frameIntervalMs);
        }

        CloseHandle(writePipe);
        DWORD waitResult = WaitForSingleObject(pi.hProcess, 10000);
        DWORD exitCode = 1;
        GetExitCodeProcess(pi.hProcess, &exitCode);
        if (waitResult != WAIT_OBJECT_0) TerminateProcess(pi.hProcess, 1);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        finalizedOk_.store(exitCode == 0, std::memory_order_relaxed);

        try {
            session.Close();
            framePool.Close();
        } catch (...) {}

        if (pCamReader) pCamReader->Release();
        if (pCamSource) { pCamSource->Shutdown(); pCamSource->Release(); }
        if (ppCamDevices) {
            for (UINT32 i = 0; i < camDeviceCount; i++) if (ppCamDevices[i]) ppCamDevices[i]->Release();
            CoTaskMemFree(ppCamDevices);
        }
        if (pCamDeviceAttrs) pCamDeviceAttrs->Release();

        if (mmcssHandle) AvRevertMmThreadCharacteristics(mmcssHandle);
    }

    std::thread worker_;
    std::atomic<bool> shouldStop_{false};
    std::atomic<bool> finalizedOk_{false};
    std::mutex errorMutex_;
    std::wstring lastError_;
};

std::mutex g_compositorHandlesMutex;
std::unordered_map<int64_t, std::unique_ptr<ExternalCompositor>> g_compositorHandles;
std::atomic<int64_t> g_nextCompositorHandle{1};

}  // namespace

extern "C" {

// [cameraDeviceName] may be an empty string -- window capture only, no
// camera overlay.
__declspec(dllexport) int64_t jyamiti_compositor_start(
    const wchar_t* cameraDeviceName, const wchar_t* outputPath, int32_t fps) {
    if (!outputPath) return 0;
    auto compositor = std::make_unique<ExternalCompositor>();
    compositor->Start(cameraDeviceName ? cameraDeviceName : L"", outputPath, fps > 0 ? fps : 15);

    int64_t handle = g_nextCompositorHandle.fetch_add(1, std::memory_order_relaxed);
    std::lock_guard<std::mutex> lock(g_compositorHandlesMutex);
    g_compositorHandles[handle] = std::move(compositor);
    return handle;
}

__declspec(dllexport) int32_t jyamiti_compositor_stop(int64_t handle) {
    ExternalCompositor* compositor = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_compositorHandlesMutex);
        auto it = g_compositorHandles.find(handle);
        if (it == g_compositorHandles.end()) return 0;
        compositor = it->second.get();
    }
    return compositor->Stop() ? 1 : 0;
}

__declspec(dllexport) int32_t jyamiti_compositor_last_error(
    int64_t handle, wchar_t* outBuffer, int32_t outBufferChars) {
    if (!outBuffer || outBufferChars <= 0) return 0;
    outBuffer[0] = L'\0';
    std::wstring message;
    {
        std::lock_guard<std::mutex> lock(g_compositorHandlesMutex);
        auto it = g_compositorHandles.find(handle);
        if (it == g_compositorHandles.end()) return 0;
        message = it->second->LastError();
    }
    wcsncpy_s(outBuffer, outBufferChars, message.c_str(), _TRUNCATE);
    return 1;
}

__declspec(dllexport) void jyamiti_compositor_destroy(int64_t handle) {
    std::lock_guard<std::mutex> lock(g_compositorHandlesMutex);
    g_compositorHandles.erase(handle);
}

}  // extern "C"
