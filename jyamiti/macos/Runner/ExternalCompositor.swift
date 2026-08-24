// ============================================================================
// UNVERIFIED -- written on a Windows machine with no Mac/Xcode/macOS SDK
// available to compile or run it. Every other native module in this app
// (external_compositor.cpp on Windows) was validated through dozens of real
// compile-and-run cycles before being trusted; this file has had NONE of
// that. Treat it as a first draft that needs real Xcode build-and-test
// before anyone relies on it -- see the "KNOWN RISK AREAS" list at the
// bottom of this comment for exactly what's most likely to need fixing
// first.
//
// macOS equivalent of windows/native_camera/external_compositor.cpp --
// captures Math Pad's own window via ScreenCaptureKit (the same OS-level
// "tap what the compositor already rendered" trick WGC does on Windows --
// SCStream's frame delivery happens on its own dedicated queue, never
// Flutter's/AppKit's main thread), optionally composites a live camera feed
// on top (Core Image, GPU-accelerated via Metal), and encodes the result
// through a piped ffmpeg process, all outside Flutter's own rendering
// pipeline. Same motivation as the Windows module: CameraEncodeMode.onCanvas
// works but visibly costs drawing smoothness (confirmed via real testing on
// Windows); this is the architectural fix, not a faster version of the same
// trick.
//
// INTEGRATION CHOICE -- unlike the Windows module (a C-ABI DLL loaded via
// dart:ffi + DynamicLibrary.open), this is exposed via a FlutterMethodChannel
// registered in MainFlutterWindow.swift. That's deliberate, not an
// inconsistency: dart:ffi on macOS would need `@_cdecl`-exported symbols
// resolved out of the *host app's own* Mach-O binary via
// DynamicLibrary.process(), which is a much more exotic, failure-prone
// pattern than on Windows (where loading a plain sibling .dll is completely
// standard) -- symbol visibility/stripping across Xcode build
// configurations is a real, hard-to-debug risk class I have no way to test
// for from here. MethodChannel is the standard, battle-tested way every
// real Flutter macOS plugin talks to native code, so it removes an entire
// category of risk, leaving only "is the ScreenCaptureKit/AVFoundation/
// CoreImage logic itself correct" -- still real, but smaller and more
// contained.
//
// DOESN'T TOUCH THE REST OF THE APP -- MathPadRecordingService.start() still
// unconditionally throws on any non-Windows platform
// ("Recording is only available on Windows right now.", see that file).
// This module is reachable in principle once that gate is relaxed for
// macOS, but is NOT wired through to anything reachable from the UI yet --
// deliberately left as a separate decision, since lifting that gate turns
// on the ENTIRE recording feature for macOS (audio capture, ffmpeg muxing,
// segment sealing, etc.), not just this one compositor, and touches
// pre-existing partial macOS groundwork elsewhere in this file that I
// didn't write and haven't verified either.
//
// KNOWN RISK AREAS (check these first if something doesn't work):
//   1. Deployment target is macOS 10.15 app-wide (project.pbxproj) --
//      ScreenCaptureKit needs 12.3+. Everything here is `@available`-guarded
//      to that, deliberately NOT bumping the whole app's minimum target
//      (that would be a much bigger, unrelated side effect). Double-check
//      the `@available` placement actually compiles cleanly at 10.15.
//   2. CoreImage's coordinate system is BOTTOM-LEFT origin, unlike
//      Direct2D's/most other 2D APIs' top-left origin -- every Y coordinate
//      below is deliberately flipped (see `flippedY`) to compensate. This
//      is exactly the kind of off-by-flip bug that's easy to get backwards
//      and only obvious once you can actually see composited output, which
//      I can't do here.
//   3. SCShareableContent / SCStream's exact async API shape (throwing vs.
//      completion-handler variants, exact SCStreamConfiguration property
//      names) can differ across SDK/macOS versions in ways I can't check
//      against the actual SDK installed for this project.
//   4. Own-window lookup depends on `MainFlutterWindow.sharedInstance`
//      actually being set before `start()` is ever called -- true for any
//      realistic app lifecycle (the window exists long before a recording
//      could start), but worth confirming.
//   5. No macOS equivalent of the Windows Job Object hard-kill protection
//      exists for the spawned ffmpeg process -- matches this file's
//      existing, pre-existing acceptance that `_tieProcessLifetimeToApp` is
//      a no-op on macOS (see mathpad_recording_service.dart lines ~492,
//      ~527), not a new gap introduced here, but still worth knowing.
//   6. `import ScreenCaptureKit` may need an explicit entry under the
//      Runner target's Build Phases > Link Binary With Libraries in
//      Xcode (project.pbxproj) if the Swift compiler doesn't auto-link it
//      in this project's exact Xcode version. Deliberately NOT hand-edited
//      into project.pbxproj here -- that file's format is fragile enough
//      that a blind edit risks corrupting the whole Xcode project (every
//      platform's build, not just this feature), which is a worse outcome
//      than just documenting the one-click GUI fix for whoever first
//      builds this in Xcode.
// ============================================================================

import Cocoa
import FlutterMacOS
import ScreenCaptureKit
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

@available(macOS 12.3, *)
final class ExternalCompositor: NSObject, SCStreamOutput, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Public entry points (called from the MethodChannel handler)

    /// Starts capture+composite+encode. Fully async; failures are reported
    /// through `lastError` (mirrors the Windows module's `LastError()` --
    /// deliberately never throws all the way back to the recording UI,
    /// since a camera/compositor failure here should degrade the same way
    /// every other camera failure in this app does, not abort the
    /// recording).
    func start(
        cameraDeviceName: String,
        outputPath: String,
        fps: Int,
        cropX: Int, cropY: Int, cropW: Int, cropH: Int,
        completion: @escaping (Bool) -> Void
    ) {
        Task {
            do {
                try await startInternal(
                    cameraDeviceName: cameraDeviceName,
                    outputPath: outputPath,
                    fps: max(1, fps),
                    cropRect: (cropW > 0 && cropH > 0)
                        ? CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
                        : nil
                )
                completion(true)
            } catch {
                setLastError("\(error)")
                completion(false)
            }
        }
    }

    /// Live crop update -- same semantics as the Windows module's
    /// `SetCrop`: only changes which sub-rectangle of the captured window
    /// gets encoded, never the output's fixed pixel dimensions (decided
    /// once in `start`, since ffmpeg's raw-video pipe can't resize
    /// mid-stream).
    func setCrop(x: Int, y: Int, w: Int, h: Int) {
        cropLock.lock()
        liveCropRect = (w > 0 && h > 0) ? CGRect(x: x, y: y, width: w, height: h) : nil
        cropLock.unlock()
    }

    /// Stops capture, closes the encoder's pipe, and waits for ffmpeg to
    /// finish writing the output file. Returns whether the output looks
    /// valid (non-empty). Async (unlike the Windows module's synchronous
    /// `Stop()`) -- MethodChannel results are naturally async, so there's
    /// no need to force this onto a blocking call the way the Windows FFI
    /// bridge did.
    func stop(completion: @escaping (Bool) -> Void) {
        Task {
            frameTimer?.cancel()
            frameTimer = nil
            if #available(macOS 12.3, *) {
                try? await stream?.stopCapture()
            }
            stream = nil
            captureSession?.stopRunning()
            captureSession = nil

            // Close ffmpeg's stdin so it finalizes the file, then wait
            // (bounded, same 10s timeout the Windows module uses) for it
            // to actually exit.
            try? ffmpegStdin?.close()
            ffmpegStdin = nil
            let exited = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                guard let process = ffmpegProcess else {
                    cont.resume(returning: true)
                    return
                }
                if !process.isRunning {
                    cont.resume(returning: true)
                    return
                }
                process.terminationHandler = { _ in cont.resume(returning: true) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                    if process.isRunning {
                        process.terminate()
                    }
                }
            }
            ffmpegProcess = nil

            let outPath = self.outputPath
            let ok = exited && outPath != nil && FileManager.default.fileExists(atPath: outPath!)
                && ((try? FileManager.default.attributesOfItem(atPath: outPath!)[.size] as? Int) ?? 0) > 0
            completion(ok)
        }
    }

    private(set) var lastError: String?
    private let errorLock = NSLock()
    private func setLastError(_ message: String) {
        errorLock.lock()
        lastError = message
        errorLock.unlock()
    }

    // MARK: - State

    private var stream: SCStream?
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var ffmpegProcess: Process?
    private var ffmpegStdin: FileHandle?
    private var outputPath: String?
    private var fps: Int = 15
    private var width: Int = 0
    private var height: Int = 0
    /// Fixed at `start()` time from the initial crop (or the full window
    /// if none) -- see `setCrop`'s doc comment for why this never changes
    /// again afterward.
    private var initialWindowSize: CGSize = .zero

    private let cropLock = NSLock()
    private var liveCropRect: CGRect?

    private let frameLock = NSLock()
    /// Latest fully-composited frame, packed tightly (rowBytes == width*4,
    /// no padding) -- written to ffmpeg's pipe by `frameTimer`, not
    /// directly by the SCStream callback. Decoupling composition from
    /// writing this way means a window frame that hasn't changed (SCStream,
    /// like WGC, only delivers a new frame when content actually changes)
    /// still gets correctly re-sent as many times as real elapsed time
    /// demands -- see `frameTimer`'s doc comment for the full reasoning
    /// (this is the exact fix the Windows module needed AFTER shipping;
    /// building it in from the start here instead of rediscovering it).
    private var latestComposedFrame: Data?
    private var latestCameraPixelBuffer: CVPixelBuffer?

    private var frameTimer: DispatchSourceTimer?
    private var captureStart: Date?
    private var framesWritten: Int64 = 0
    /// Same safety cap as the Windows module's `kMaxCatchUpFramesPerIteration`
    /// -- caps how many duplicate frames one timer tick will flush at once,
    /// so a genuine stall can't turn into one enormous blocking burst write.
    private let maxCatchUpFramesPerTick: Int64 = 6

    private lazy var ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext() // Software fallback -- slower, but never nil.
    }()

    // MARK: - Setup

    private func startInternal(
        cameraDeviceName: String,
        outputPath: String,
        fps: Int,
        cropRect: CGRect?
    ) async throws {
        self.fps = fps
        self.outputPath = outputPath
        self.liveCropRect = cropRect

        guard let targetWindow = await MainActor.run(body: { MainFlutterWindow.sharedInstance }) else {
            throw CompositorError.message("Could not find the app's own window")
        }

        // This app's own on-screen window, in points -- multiplied by the
        // backing scale factor below to get real pixel dimensions (Retina
        // displays report points, not pixels, for window frames).
        let (windowFrameInPoints, scale, windowNumber) = await MainActor.run {
            (targetWindow.frame, targetWindow.backingScaleFactor, targetWindow.windowNumber)
        }
        let fullPixelWidth = Int(windowFrameInPoints.width * scale)
        let fullPixelHeight = Int(windowFrameInPoints.height * scale)
        initialWindowSize = CGSize(width: fullPixelWidth, height: fullPixelHeight)

        // Output/pipe dimensions fixed for the whole recording, exactly the
        // same reasoning as the Windows module: from the crop if one was
        // given (even-numbered, since yuv420p needs even width/height),
        // otherwise the full window.
        let rawW = cropRect.map { Int($0.width) } ?? fullPixelWidth
        let rawH = cropRect.map { Int($0.height) } ?? fullPixelHeight
        width = max(2, (rawW / 2) * 2)
        height = max(2, (rawH / 2) * 2)

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        // Cocoa's own windowNumber for this app's window doubles as
        // ScreenCaptureKit's windowID -- both are the same underlying
        // CGWindowID, so no PID-enumeration dance is needed the way
        // Windows' FindOwnWindow() needs one.
        guard let scWindow = content.windows.first(where: {
            $0.windowID == CGWindowID(windowNumber)
        }) else {
            throw CompositorError.message("Could not find this app's window in ScreenCaptureKit's window list -- Screen Recording permission may not be granted yet (System Settings > Privacy & Security > Screen Recording), or the app needs restarting after granting it")
        }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        config.width = fullPixelWidth
        config.height = fullPixelHeight
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 5
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))

        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try newStream.addStreamOutput(
            self, type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "jyamiti.compositor.screen")
        )
        try await newStream.startCapture()
        stream = newStream

        if !cameraDeviceName.isEmpty {
            setUpCamera(named: cameraDeviceName)
        }

        try spawnFfmpeg(outputPath: outputPath)

        captureStart = Date()
        framesWritten = 0
        let interval = 1.0 / Double(fps)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "jyamiti.compositor.writer"))
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in self?.onWriterTick() }
        timer.resume()
        frameTimer = timer
    }

    private func setUpCamera(named deviceName: String) {
        // Best-effort only -- a camera failure here costs just the overlay,
        // never the recording, same "camera trouble costs the camera, not
        // the recording" philosophy as everywhere else in this app.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        guard let device = discovery.devices.first(where: { $0.localizedName == deviceName })
            ?? AVCaptureDevice.default(for: .video)
        else { return }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }

        let session = AVCaptureSession()
        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "jyamiti.compositor.camera"))
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        captureSession = session
        videoOutput = output
        session.startRunning()
    }

    private func spawnFfmpeg(outputPath: String) throws {
        var ffmpegURL = Bundle.main.executableURL!
            .deletingLastPathComponent()
            .appendingPathComponent("ffmpeg")
        if !FileManager.default.fileExists(atPath: ffmpegURL.path) {
            let homebrewURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            let intelURL = URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
            let usrURL = URL(fileURLWithPath: "/usr/bin/ffmpeg")
            if FileManager.default.fileExists(atPath: homebrewURL.path) {
                ffmpegURL = homebrewURL
            } else if FileManager.default.fileExists(atPath: intelURL.path) {
                ffmpegURL = intelURL
            } else if FileManager.default.fileExists(atPath: usrURL.path) {
                ffmpegURL = usrURL
            } else {
                throw CompositorError.message("ffmpeg not found next to the app bundle's executable or in /opt/homebrew/bin/ffmpeg")
            }
        }

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-y",
            "-f", "rawvideo",
            "-pixel_format", "bgra",
            "-video_size", "\(width)x\(height)",
            "-framerate", "\(fps)",
            "-i", "pipe:0",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-preset", "veryfast",
            "-crf", "20",
            "-bf", "0",
            outputPath,
        ]
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        ffmpegProcess = process
        ffmpegStdin = stdinPipe.fileHandleForWriting
    }

    // MARK: - Frame delivery (SCStream + AVFoundation delegates)

    // SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        composite(windowPixelBuffer: pixelBuffer)
    }

    // AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameLock.lock()
        latestCameraPixelBuffer = pixelBuffer
        frameLock.unlock()
    }

    /// Crops/composites the just-captured window frame (+ whatever the
    /// most recent camera frame was, if any) into `latestComposedFrame`,
    /// tightly packed and ready for a single pipe write. Runs on
    /// SCStream's own dedicated queue -- never Flutter's/AppKit's main
    /// thread, which is the entire point of this module.
    private func composite(windowPixelBuffer: CVPixelBuffer) {
        let windowImage = CIImage(cvImageBuffer: windowPixelBuffer)
        let fullHeight = initialWindowSize.height

        cropLock.lock()
        let crop = liveCropRect
        cropLock.unlock()

        // CoreImage's coordinate origin is BOTTOM-LEFT, unlike the
        // top-left origin the crop rect (and everything else in this
        // app) is measured in -- flip Y here, once, rather than trying to
        // keep two different coordinate conventions straight everywhere
        // else. See this file's header comment, risk area #2.
        func flippedY(_ rect: CGRect, in totalHeight: CGFloat) -> CGRect {
            CGRect(x: rect.minX, y: totalHeight - rect.maxY, width: rect.width, height: rect.height)
        }

        var composed = crop != nil
            ? windowImage.cropped(to: flippedY(crop!, in: fullHeight))
                .transformed(by: CGAffineTransform(
                    translationX: -flippedY(crop!, in: fullHeight).minX,
                    y: -flippedY(crop!, in: fullHeight).minY
                ))
            : windowImage

        frameLock.lock()
        let camBuffer = latestCameraPixelBuffer
        frameLock.unlock()

        if let camBuffer = camBuffer {
            let camImage = CIImage(cvImageBuffer: camBuffer)
            let camW = camImage.extent.width
            let camH = camImage.extent.height
            let cropSize = min(camW, camH)
            let camCropX = (camW - cropSize) / 2
            // Matches the exact PIP spec every other camera-overlay path
            // in this app uses -- crop=ih:ih, scale to 240x240, white
            // border, top-right 24px inset.
            let boxSize: CGFloat = 240
            let inset: CGFloat = 24
            let squareCam = camImage
                .cropped(to: CGRect(x: camCropX, y: 0, width: cropSize, height: cropSize))
                .transformed(by: CGAffineTransform(
                    translationX: -camCropX, y: 0
                ))
                .transformed(by: CGAffineTransform(
                    scaleX: boxSize / cropSize, y: boxSize / cropSize
                ))
            let destX = CGFloat(width) - inset - boxSize
            let destY = CGFloat(height) - inset - boxSize // bottom-left-origin: top-right inset becomes this
            let positionedCam = squareCam.transformed(by: CGAffineTransform(translationX: destX, y: destY))

            // White border -- a solid white rect very slightly larger than
            // the camera box, composited BEHIND it (same "background rect
            // first, camera on top" trick the Windows/D2D version uses for
            // its border via DrawRectangle, adapted since CoreImage has no
            // direct stroked-rect primitive).
            let borderRect = CGRect(x: destX - 4, y: destY - 4, width: boxSize + 8, height: boxSize + 8)
            let borderImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.9))
                .cropped(to: borderRect)

            composed = positionedCam.composited(over: borderImage.composited(over: composed))
        }

        let outRect = CGRect(x: 0, y: 0, width: width, height: height)
        var packed = Data(count: width * height * 4)
        packed.withUnsafeMutableBytes { (rawPtr: UnsafeMutableRawBufferPointer) in
            guard let base = rawPtr.baseAddress else { return }
            ciContext.render(
                composed, toBitmap: base, rowBytes: width * 4,
                bounds: outRect, format: .BGRA8, colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }

        frameLock.lock()
        latestComposedFrame = packed
        frameLock.unlock()
    }

    /// Wall-clock-driven frame writer -- fires every `1/fps` seconds and
    /// writes however many frame slots real elapsed time actually calls
    /// for (usually 1, more to catch up after a stall, capped at
    /// `maxCatchUpFramesPerTick`), instead of assuming one timer tick
    /// always equals exactly one output frame. This is the exact fix the
    /// Windows compositor needed AFTER it shipped (frames written strictly
    /// per-tick drifted the encoded duration away from real elapsed time
    /// whenever a tick's own work ran long) -- built in from the start
    /// here rather than waiting to rediscover the same bug.
    private func onWriterTick() {
        guard let start = captureStart, let stdin = ffmpegStdin else { return }
        frameLock.lock()
        let frame = latestComposedFrame
        frameLock.unlock()
        guard let frame = frame else { return }

        let elapsed = Date().timeIntervalSince(start)
        let fillTo = min(
            Int64(elapsed * Double(fps)),
            framesWritten + maxCatchUpFramesPerTick
        )
        var slot = framesWritten
        while slot < fillTo {
            do {
                try stdin.write(contentsOf: frame)
            } catch {
                // Pipe likely closed (ffmpeg exited) -- stop trying for
                // the rest of this recording rather than spamming a
                // failing write every tick.
                setLastError("Writing to the encoder's pipe failed: \(error)")
                frameTimer?.cancel()
                frameTimer = nil
                return
            }
            slot += 1
        }
        framesWritten = fillTo
    }
}

@available(macOS 12.3, *)
private enum CompositorError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let m): return m }
    }
}
