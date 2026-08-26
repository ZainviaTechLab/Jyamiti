// Conditional-import barrel for the native low-latency Pen-stroke overlay
// (Windows only, for now -- see windows/runner/live_ink_overlay.h's doc
// comment for the full design and rationale). Exposes `LiveInkOverlay`
// with an identical API on every platform; the stub is a complete no-op
// (`armStroke` always returns false, meaning callers always fall back to
// normal Flutter-side drawing) so mathpad.dart never needs its own
// platform gating beyond checking `LiveInkOverlay.isSupported`.
//
// Uses a `MethodChannel` (not raw FFI/win32, unlike camera_capture_native's
// external-compositor bridge) -- MethodChannel itself compiles fine
// everywhere including web, so the ONLY reason this needs a conditional
// import at all is `live_ink_overlay_io.dart`'s `Platform.isWindows` check
// (`dart:io`, unavailable on web -- same class of problem the win32/
// package:ffi web-build break earlier this session came from).
export 'live_ink_overlay_stub.dart'
    if (dart.library.io) 'live_ink_overlay_io.dart';
