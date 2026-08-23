// ============================================================================
// UNVERIFIED -- written on a Windows machine with no Linux box, no X11/GTK
// dev headers, and no compiler available to even attempt building this, let
// alone run it. This has had LESS verification than the also-unverified
// macOS port (macos/Runner/ExternalCompositor.swift) -- there, at least the
// Dart-side wiring got real analyzer/build verification; the C++ below has
// had zero compile-time checking of any kind, not even a syntax pass.
// Treat this as a rough first draft, not a working implementation.
//
// Linux equivalent of windows/native_camera/external_compositor.cpp and
// macos/Runner/ExternalCompositor.swift -- captures Math Pad's own window
// via the X11 Composite extension (the same "tap what the compositor
// already rendered" idea as WGC/ScreenCaptureKit), optionally composites a
// live camera feed on top (plain CPU pixel blending -- see risk area #3
// below for why this isn't GPU-accelerated like the other two platforms),
// and encodes the result through a piped ffmpeg process.
//
// REAL, UNAVOIDABLE ENVIRONMENTAL DEPENDENCY: XComposite's
// "redirect + name window pixmap" trick (the whole reason this can be
// smooth/off-thread at all) only works if a COMPOSITING window manager is
// actually running. Most modern desktops (GNOME, KDE, most others) run one
// by default, but some minimal/tiling setups (bare i3, dwm, etc.) don't --
// on those, this will fail outright (see the SetError call after
// `XCompositeQueryExtension`) with no fallback. There's no equivalent
// concern on Windows (DWM composition has been mandatory since Windows 8)
// or macOS (the WindowServer always composites).
//
// FRAGMENTED BY DESIGN, NOT JUST BY THIS FILE'S CHOICE -- this only covers
// X11. Wayland has no XComposite equivalent at all; its capture path is the
// completely different xdg-desktop-portal ScreenCast portal + PipeWire,
// which needs its own separate implementation this file does NOT attempt.
// A growing share of Linux desktops (recent GNOME/KDE defaults) run Wayland
// natively -- on a pure-Wayland session (no XWayland X11 compatibility
// window available for this app), this module will fail to even find an
// X11 connection. See `jyamiti_compositor_start`'s error handling.
//
// INTEGRATION CHOICE -- unlike macOS (MethodChannel, since dart:ffi's
// DynamicLibrary.process() there is comparatively exotic/fragile), this
// uses the SAME dart:ffi + shared-library pattern as Windows: Linux's
// dart:ffi story for loading a plain sibling .so is exactly as standard
// and well-trodden as Windows' .dll loading, so there was no reason to
// reach for a different mechanism here. Same C ABI as the Windows module
// (jyamiti_compositor_start/_set_crop/_stop/_last_error/_destroy) --
// camera_capture_native.dart's existing FFI bindings section is reused
// almost unchanged, just pointed at libjyamiti_camera.so instead of
// jyamiti_camera.dll.
//
// DOESN'T TOUCH THE REST OF THE APP -- same as the macOS port,
// MathPadRecordingService.start() still unconditionally throws on any
// non-Windows platform. This module is not reachable from the UI yet.
//
// KNOWN RISK AREAS (highest risk first):
//   1. V4L2 camera capture (`SetUpCamera` below) -- ioctl-based APIs are
//      exactly the kind of "get one struct field order or enum value
//      wrong and it silently misbehaves instead of failing loudly" code
//      that's hardest to get right without ever running it. Best-effort
//      only, matching every other platform's "camera trouble costs the
//      camera, never the recording" philosophy -- if this is wrong, the
//      window capture below should still work independently.
//   2. Requesting V4L2_PIX_FMT_YUYV specifically (not BGR/RGB directly)
//      and hand-rolling the YUYV->BGRA conversion (`YuyvToBgra`) --
//      chosen because YUYV is the most widely supported raw format across
//      real webcam hardware (more so than direct RGB/BGR, which many
//      cheap cameras don't offer at all), but this is unverified against
//      any real device.
//   3. Pixel compositing here is plain CPU memcpy/blend, NOT GPU-
//      accelerated the way D2D (Windows) or Core Image (macOS) are. This
//      still achieves the core "off Flutter's UI thread" smoothness
//      property (this all runs on its own thread, never blocking
//      drawing), but is a deliberately simpler, lower-performance choice
//      to reduce the amount of blind, unverifiable GLX/EGL context and
//      shader code -- a real GPU path would be a reasonable upgrade once
//      this is confirmed working at all.
//   4. Uses plain `XGetImage` (always available, no setup) rather than
//      the faster `XShmGetImage` (MIT-SHM shared memory) -- simpler and
//      more likely to be structurally correct, at a real performance
//      cost someone with a real X11 session could profile and upgrade.
//   5. Assumes a 32-bit-per-pixel TrueColor/DirectColor visual with
//      standard RGB byte ordering (overwhelmingly the common case on
//      modern Linux desktops) -- an unusual visual configuration could
//      produce corrupted colors. Checked via `bits_per_pixel`, but not
///     exhaustively handled for every possible visual.
//   6. Own-window lookup (`FindOwnWindow`) opens an INDEPENDENT Xlib
//      connection via `XOpenDisplay(nullptr)`, deliberately separate from
//      GTK/GDK's own connection -- standard practice for a module that
//      needs X11 access off the GTK main thread without fighting over
//      thread affinity, but relies on the window manager supporting the
//      EWMH `_NET_CLIENT_LIST`/`_NET_WM_PID` properties (true for
//      essentially every modern WM, but not a hard guarantee).
// ============================================================================

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xcomposite.h>
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>
#include <memory>
#include <cstdio>
#include <sys/wait.h>
#include <signal.h>

namespace {

// Independent X11 connection + EWMH walk to find this process's own
// top-level window -- see risk area #6 above. Mirrors the role of
// Windows' FindOwnWindow()/macOS's MainFlutterWindow.sharedInstance.
Window FindOwnWindow(Display* display) {
    Window root = DefaultRootWindow(display);
    Atom clientListAtom = XInternAtom(display, "_NET_CLIENT_LIST", True);
    Atom pidAtom = XInternAtom(display, "_NET_WM_PID", True);
    if (clientListAtom == None || pidAtom == None) return 0;

    Atom actualType;
    int actualFormat;
    unsigned long numItems, bytesAfter;
    unsigned char* data = nullptr;
    int status = XGetWindowProperty(
        display, root, clientListAtom, 0, ~0L, False, XA_WINDOW,
        &actualType, &actualFormat, &numItems, &bytesAfter, &data);
    if (status != Success || !data) return 0;

    Window* windows = reinterpret_cast<Window*>(data);
    pid_t myPid = getpid();
    Window found = 0;
    for (unsigned long i = 0; i < numItems; i++) {
        Atom pidType;
        int pidFormat;
        unsigned long pidItems, pidBytesAfter;
        unsigned char* pidData = nullptr;
        if (XGetWindowProperty(
                display, windows[i], pidAtom, 0, 1, False, XA_CARDINAL,
                &pidType, &pidFormat, &pidItems, &pidBytesAfter, &pidData) == Success &&
            pidData) {
            if (pidItems > 0 && (pid_t)(*reinterpret_cast<unsigned long*>(pidData)) == myPid) {
                found = windows[i];
                XFree(pidData);
                break;
            }
            XFree(pidData);
        }
    }
    XFree(data);
    return found;
}

std::string ResolveFfmpegPath() {
    char exePath[4096] = {0};
    ssize_t len = readlink("/proc/self/exe", exePath, sizeof(exePath) - 1);
    std::string dir = ".";
    if (len > 0) {
        exePath[len] = '\0';
        std::string full(exePath);
        size_t slash = full.find_last_of('/');
        if (slash != std::string::npos) dir = full.substr(0, slash);
    }
    return dir + "/ffmpeg";
}

// Standard BT.601 YUYV (YUY2) -> BGRA conversion -- see risk area #2.
// YUYV packs 2 pixels per 4 bytes (Y0 U Y1 V); this expands each pair to
// 2 full BGRA pixels.
void YuyvToBgra(const uint8_t* yuyv, uint8_t* bgra, int width, int height) {
    auto clamp = [](int v) { return (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v)); };
    int pixels = width * height;
    for (int i = 0, j = 0; i < pixels * 2; i += 4, j += 8) {
        int y0 = yuyv[i], u = yuyv[i + 1] - 128, y1 = yuyv[i + 2], v = yuyv[i + 3] - 128;
        for (int k = 0; k < 2; k++) {
            int y = (k == 0) ? y0 : y1;
            int r = y + ((91881 * v) >> 16);
            int g = y - ((22554 * u + 46802 * v) >> 16);
            int b = y + ((116130 * u) >> 16);
            bgra[j + k * 4 + 0] = clamp(b);
            bgra[j + k * 4 + 1] = clamp(g);
            bgra[j + k * 4 + 2] = clamp(r);
            bgra[j + k * 4 + 3] = 255;
        }
    }
}

class ExternalCompositor {
public:
    // See external_compositor.cpp's (Windows) equivalent doc comment --
    // same semantics: cropW/cropH <= 0 means "capture the full window";
    // otherwise their size becomes the FIXED output/pipe dimensions for
    // the whole recording, decided once here.
    void Start(std::string cameraDevicePath, std::string outputPath, int fps,
               int32_t cropX, int32_t cropY, int32_t cropW, int32_t cropH) {
        cropX_.store(cropX, std::memory_order_relaxed);
        cropY_.store(cropY, std::memory_order_relaxed);
        cropW_.store(cropW, std::memory_order_relaxed);
        cropH_.store(cropH, std::memory_order_relaxed);
        worker_ = std::thread([this, cameraDevicePath = std::move(cameraDevicePath),
                                outputPath = std::move(outputPath), fps, cropW, cropH]() {
            Run(cameraDevicePath, outputPath, fps, cropW, cropH);
        });
    }

    bool Stop() {
        shouldStop_.store(true, std::memory_order_relaxed);
        if (worker_.joinable()) worker_.join();
        return finalizedOk_.load(std::memory_order_relaxed);
    }

    void SetCrop(int32_t x, int32_t y, int32_t w, int32_t h) {
        cropX_.store(x, std::memory_order_relaxed);
        cropY_.store(y, std::memory_order_relaxed);
        cropW_.store(w, std::memory_order_relaxed);
        cropH_.store(h, std::memory_order_relaxed);
    }

    std::string LastError() {
        std::lock_guard<std::mutex> lock(errorMutex_);
        return lastError_;
    }

private:
    void SetError(const std::string& what) {
        std::lock_guard<std::mutex> lock(errorMutex_);
        lastError_ = what;
    }

    void Run(const std::string& cameraDevicePath, const std::string& outputPath, int fps,
             int32_t initialCropW, int32_t initialCropH) {
        Display* display = XOpenDisplay(nullptr);
        if (!display) {
            SetError("Could not open an X11 display connection -- likely a pure-Wayland "
                      "session with no X11/XWayland available (see this file's header "
                      "comment)");
            return;
        }

        int compEventBase, compErrorBase;
        if (!XCompositeQueryExtension(display, &compEventBase, &compErrorBase)) {
            SetError("XComposite extension not available");
            XCloseDisplay(display);
            return;
        }

        Window target = FindOwnWindow(display);
        if (!target) {
            SetError("Could not find this app's own window via _NET_CLIENT_LIST/"
                      "_NET_WM_PID -- the window manager may not support these "
                      "standard EWMH properties");
            XCloseDisplay(display);
            return;
        }

        XWindowAttributes attrs;
        XGetWindowAttributes(display, target, &attrs);
        const int fullWidth = attrs.width;
        const int fullHeight = attrs.height;

        // Redirects this window's rendering into an off-screen backing
        // pixmap maintained by the compositing window manager (see this
        // file's header comment on the compositing-WM dependency) --
        // CompositeRedirectAutomatic means the WM keeps updating it the
        // normal way (as if still on-screen), rather than this app having
        // to explicitly request each update.
        XCompositeRedirectWindow(display, target, CompositeRedirectAutomatic);

        const bool haveInitialCrop = initialCropW > 0 && initialCropH > 0;
        int width = std::max(2, ((haveInitialCrop ? initialCropW : fullWidth) / 2) * 2);
        int height = std::max(2, ((haveInitialCrop ? initialCropH : fullHeight) / 2) * 2);

        // Camera setup (V4L2) -- best-effort, see risk areas #1/#2.
        int camFd = -1;
        int camW = 0, camH = 0;
        std::vector<uint8_t> camBgra;
        void* camMmapBuf = nullptr;
        size_t camMmapLen = 0;
        bool haveCamera = false;

        if (!cameraDevicePath.empty()) {
            camFd = open(cameraDevicePath.c_str(), O_RDWR | O_NONBLOCK);
            if (camFd >= 0) {
                v4l2_format fmt = {};
                fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
                ioctl(camFd, VIDIOC_G_FMT, &fmt);
                fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
                if (ioctl(camFd, VIDIOC_S_FMT, &fmt) >= 0 &&
                    fmt.fmt.pix.pixelformat == V4L2_PIX_FMT_YUYV) {
                    camW = fmt.fmt.pix.width;
                    camH = fmt.fmt.pix.height;

                    v4l2_requestbuffers req = {};
                    req.count = 2;
                    req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
                    req.memory = V4L2_MEMORY_MMAP;
                    if (ioctl(camFd, VIDIOC_REQBUFS, &req) >= 0 && req.count >= 1) {
                        v4l2_buffer buf = {};
                        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
                        buf.memory = V4L2_MEMORY_MMAP;
                        buf.index = 0;
                        if (ioctl(camFd, VIDIOC_QUERYBUF, &buf) >= 0) {
                            camMmapLen = buf.length;
                            camMmapBuf = mmap(nullptr, buf.length, PROT_READ | PROT_WRITE,
                                               MAP_SHARED, camFd, buf.m.offset);
                            if (camMmapBuf != MAP_FAILED &&
                                ioctl(camFd, VIDIOC_QBUF, &buf) >= 0) {
                                v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
                                if (ioctl(camFd, VIDIOC_STREAMON, &type) >= 0) {
                                    camBgra.resize((size_t)camW * camH * 4);
                                    haveCamera = true;
                                }
                            }
                        }
                    }
                }
                if (!haveCamera) { close(camFd); camFd = -1; }
            }
        }

        // ffmpeg process, reading raw BGRA frames from our stdin -- same
        // shape as every other platform's compositor.
        int pipeFds[2];
        if (pipe(pipeFds) != 0) {
            SetError("pipe() failed");
            XCloseDisplay(display);
            return;
        }
        std::string ffmpegPath = ResolveFfmpegPath();
        char widthArg[32], heightArg[32], sizeArg[64], fpsArg[16];
        snprintf(sizeArg, sizeof(sizeArg), "%dx%d", width, height);
        snprintf(fpsArg, sizeof(fpsArg), "%d", fps);
        pid_t ffmpegPid = fork();
        if (ffmpegPid == 0) {
            // Child: wire stdin to the read end, silence stdout/stderr,
            // exec ffmpeg.
            dup2(pipeFds[0], STDIN_FILENO);
            close(pipeFds[0]);
            close(pipeFds[1]);
            int devNull = open("/dev/null", O_WRONLY);
            if (devNull >= 0) { dup2(devNull, STDOUT_FILENO); dup2(devNull, STDERR_FILENO); }
            execl(ffmpegPath.c_str(), "ffmpeg", "-y",
                  "-f", "rawvideo", "-pixel_format", "bgra",
                  "-video_size", sizeArg, "-framerate", fpsArg, "-i", "pipe:0",
                  "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "veryfast",
                  "-crf", "20", "-bf", "0", outputPath.c_str(), (char*)nullptr);
            _exit(127); // exec failed
        }
        close(pipeFds[0]);
        int writeFd = pipeFds[1];
        if (ffmpegPid < 0) {
            SetError("fork() failed");
            close(writeFd);
            XCloseDisplay(display);
            return;
        }

        std::vector<uint8_t> frameBuf((size_t)width * height * 4);
        using Clock = std::chrono::steady_clock;
        const auto captureStart = Clock::now();
        int64_t framesWritten = 0;
        const int64_t kMaxCatchUpFramesPerTick = 6;
        const int frameIntervalMs = std::max(1, 1000 / std::max(1, fps));

        while (!shouldStop_.load(std::memory_order_relaxed)) {
            if (haveCamera) {
                v4l2_buffer buf = {};
                buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
                buf.memory = V4L2_MEMORY_MMAP;
                if (ioctl(camFd, VIDIOC_DQBUF, &buf) >= 0) {
                    YuyvToBgra(reinterpret_cast<uint8_t*>(camMmapBuf), camBgra.data(), camW, camH);
                    ioctl(camFd, VIDIOC_QBUF, &buf);
                }
                // EAGAIN (no frame ready yet, non-blocking fd) is expected
                // and fine -- camBgra just keeps whatever it last had.
            }

            Pixmap pixmap = XCompositeNameWindowPixmap(display, target);
            if (pixmap) {
                XImage* image = XGetImage(display, pixmap, 0, 0, fullWidth, fullHeight,
                                           AllPlanes, ZPixmap);
                if (image && image->bits_per_pixel == 32) {
                    const int32_t liveCropX = cropX_.load(std::memory_order_relaxed);
                    const int32_t liveCropY = cropY_.load(std::memory_order_relaxed);
                    const int32_t liveCropW = cropW_.load(std::memory_order_relaxed);
                    const int32_t liveCropH = cropH_.load(std::memory_order_relaxed);
                    const bool haveCrop = liveCropW > 0 && liveCropH > 0;
                    const int srcX0 = haveCrop ? std::max(0, liveCropX) : 0;
                    const int srcY0 = haveCrop ? std::max(0, liveCropY) : 0;

                    for (int y = 0; y < height; y++) {
                        int srcY = std::min(fullHeight - 1, srcY0 + y);
                        uint8_t* dstRow = frameBuf.data() + (size_t)y * width * 4;
                        for (int x = 0; x < width; x++) {
                            int srcX = std::min(fullWidth - 1, srcX0 + x);
                            unsigned long pixel = XGetPixel(image, srcX, srcY);
                            dstRow[x * 4 + 0] = (uint8_t)(pixel & 0xFF);         // B
                            dstRow[x * 4 + 1] = (uint8_t)((pixel >> 8) & 0xFF);  // G
                            dstRow[x * 4 + 2] = (uint8_t)((pixel >> 16) & 0xFF); // R
                            dstRow[x * 4 + 3] = 255;
                        }
                    }

                    if (haveCamera) {
                        // Matches the exact PIP spec every other camera-
                        // overlay path in this app uses -- crop=ih:ih,
                        // scale to 240x240, white border, top-right 24px
                        // inset. Nearest-neighbor scaling (no
                        // interpolation) -- simplest correct option given
                        // this is plain CPU compositing (see risk area #3).
                        const int boxSize = 240, inset = 24;
                        const int cropSize = std::min(camW, camH);
                        const int camCropX = (camW - cropSize) / 2;
                        const int destX = width - inset - boxSize;
                        const int destY = inset;
                        for (int by = -4; by < boxSize + 4; by++) {
                            int dy = destY + by;
                            if (dy < 0 || dy >= height) continue;
                            for (int bx = -4; bx < boxSize + 4; bx++) {
                                int dx = destX + bx;
                                if (dx < 0 || dx >= width) continue;
                                uint8_t* dst = frameBuf.data() + ((size_t)dy * width + dx) * 4;
                                if (bx < 0 || bx >= boxSize || by < 0 || by >= boxSize) {
                                    // White border region.
                                    dst[0] = dst[1] = dst[2] = 255; dst[3] = 255;
                                    continue;
                                }
                                int camX = camCropX + bx * cropSize / boxSize;
                                int camY = by * cropSize / boxSize;
                                camX = std::min(camW - 1, std::max(0, camX));
                                camY = std::min(camH - 1, std::max(0, camY));
                                uint8_t* src = camBgra.data() + ((size_t)camY * camW + camX) * 4;
                                std::memcpy(dst, src, 4);
                            }
                        }
                    }
                }
                if (image) XDestroyImage(image);
                XFreePixmap(display, pixmap);
            }

            const int64_t elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                Clock::now() - captureStart).count();
            const int64_t fillTo = std::min(
                (int64_t)elapsedMs * fps / 1000, framesWritten + kMaxCatchUpFramesPerTick);
            bool writeOk = true;
            for (int64_t slot = framesWritten; slot < fillTo && writeOk; slot++) {
                ssize_t written = write(writeFd, frameBuf.data(), frameBuf.size());
                if (written != (ssize_t)frameBuf.size()) writeOk = false;
            }
            if (!writeOk) {
                SetError("Writing to the encoder's pipe failed -- it may have exited");
                break;
            }
            framesWritten = fillTo;

            usleep(frameIntervalMs * 1000);
        }

        close(writeFd);
        int status = 0;
        // Bounded wait (10s, matching the other two platforms), then a
        // hard kill if ffmpeg hasn't finished by then.
        for (int i = 0; i < 100; i++) {
            pid_t r = waitpid(ffmpegPid, &status, WNOHANG);
            if (r == ffmpegPid) break;
            usleep(100 * 1000);
        }
        if (waitpid(ffmpegPid, &status, WNOHANG) != ffmpegPid) {
            kill(ffmpegPid, SIGKILL);
            waitpid(ffmpegPid, &status, 0);
        }
        finalizedOk_.store(WIFEXITED(status) && WEXITSTATUS(status) == 0, std::memory_order_relaxed);

        if (haveCamera) {
            v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
            ioctl(camFd, VIDIOC_STREAMOFF, &type);
            if (camMmapBuf) munmap(camMmapBuf, camMmapLen);
            close(camFd);
        }
        XCompositeUnredirectWindow(display, target, CompositeRedirectAutomatic);
        XCloseDisplay(display);
    }

    std::thread worker_;
    std::atomic<bool> shouldStop_{false};
    std::atomic<bool> finalizedOk_{false};
    std::atomic<int32_t> cropX_{0}, cropY_{0}, cropW_{0}, cropH_{0};
    std::mutex errorMutex_;
    std::string lastError_;
};

std::mutex g_handlesMutex;
std::unordered_map<int64_t, std::unique_ptr<ExternalCompositor>> g_handles;
std::atomic<int64_t> g_nextHandle{1};

}  // namespace

extern "C" {

// Same C ABI shape as the Windows module (external_compositor.cpp) --
// [cameraDevicePath] is a V4L2 device path (e.g. "/dev/video0"), empty
// string for no camera. [cropW]/[cropH] <= 0 means "capture the full
// window".
int64_t jyamiti_compositor_start(
    const char* cameraDevicePath, const char* outputPath, int32_t fps,
    int32_t cropX, int32_t cropY, int32_t cropW, int32_t cropH) {
    if (!outputPath) return 0;
    auto compositor = std::make_unique<ExternalCompositor>();
    compositor->Start(cameraDevicePath ? cameraDevicePath : "", outputPath,
                       fps > 0 ? fps : 15, cropX, cropY, cropW, cropH);

    int64_t handle = g_nextHandle.fetch_add(1, std::memory_order_relaxed);
    std::lock_guard<std::mutex> lock(g_handlesMutex);
    g_handles[handle] = std::move(compositor);
    return handle;
}

int32_t jyamiti_compositor_set_crop(int64_t handle, int32_t x, int32_t y, int32_t w, int32_t h) {
    std::lock_guard<std::mutex> lock(g_handlesMutex);
    auto it = g_handles.find(handle);
    if (it == g_handles.end()) return 0;
    it->second->SetCrop(x, y, w, h);
    return 1;
}

int32_t jyamiti_compositor_stop(int64_t handle) {
    ExternalCompositor* compositor = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_handlesMutex);
        auto it = g_handles.find(handle);
        if (it == g_handles.end()) return 0;
        compositor = it->second.get();
    }
    return compositor->Stop() ? 1 : 0;
}

int32_t jyamiti_compositor_last_error(int64_t handle, char* outBuffer, int32_t outBufferChars) {
    if (!outBuffer || outBufferChars <= 0) return 0;
    outBuffer[0] = '\0';
    std::string message;
    {
        std::lock_guard<std::mutex> lock(g_handlesMutex);
        auto it = g_handles.find(handle);
        if (it == g_handles.end()) return 0;
        message = it->second->LastError();
    }
    strncpy(outBuffer, message.c_str(), outBufferChars - 1);
    outBuffer[outBufferChars - 1] = '\0';
    return 1;
}

void jyamiti_compositor_destroy(int64_t handle) {
    std::lock_guard<std::mutex> lock(g_handlesMutex);
    g_handles.erase(handle);
}

}  // extern "C"
