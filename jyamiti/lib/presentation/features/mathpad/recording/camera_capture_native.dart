import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart' as ffi2;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path/path.dart' as p;

// Dart FFI bridge to `jyamiti_camera.dll` -- the native module backing
// MathPadRecordingService's "precise" sync method for BOTH the webcam
// ([NativeCameraCapture], `camera_capture.cpp`) and the microphone
// ([NativeAudioCapture], `audio_capture.cpp`). See those two files for
// the full explanation of why each exists as a native module instead of
// relying on ffmpeg/the `record` package: those can only report a stream
// started "close to" a moment (bounded by how often ffmpeg's stderr
// status line prints, or how soon after a `start()` call resolves);
// Media Foundation/WASAPI hand back each frame/packet at the exact
// instant the driver delivers it, letting this read a genuinely exact,
// sub-millisecond wall-clock timestamp for the very first one.
//
// Camera C ABI (see camera_capture.cpp for the canonical signatures):
//   int64_t jyamiti_camera_start(const wchar_t* deviceName, const wchar_t* outputPath);
//   int32_t jyamiti_camera_is_first_frame_ready(int64_t handle);
//   int64_t jyamiti_camera_first_frame_unix_micros(int64_t handle);
//   int32_t jyamiti_camera_stop(int64_t handle);
//   int32_t jyamiti_camera_last_error(int64_t handle, wchar_t* outBuffer, int32_t outBufferChars);
//   void    jyamiti_camera_destroy(int64_t handle);
//
// Audio C ABI is the same shape minus the device name (see
// audio_capture.cpp): jyamiti_audio_start/_is_first_frame_ready/
// _first_frame_unix_micros/_stop/_last_error/_destroy.

typedef _StartNative = ffi.Int64 Function(
    ffi.Pointer<ffi2.Utf16> deviceName, ffi.Pointer<ffi2.Utf16> outputPath);
typedef _StartDart = int Function(
    ffi.Pointer<ffi2.Utf16> deviceName, ffi.Pointer<ffi2.Utf16> outputPath);

typedef _HandleToIntNative = ffi.Int32 Function(ffi.Int64 handle);
typedef _HandleToIntDart = int Function(int handle);

typedef _HandleToInt64Native = ffi.Int64 Function(ffi.Int64 handle);
typedef _HandleToInt64Dart = int Function(int handle);

typedef _LastErrorNative = ffi.Int32 Function(
    ffi.Int64 handle, ffi.Pointer<ffi2.Utf16> outBuffer, ffi.Int32 outBufferChars);
typedef _LastErrorDart = int Function(
    int handle, ffi.Pointer<ffi2.Utf16> outBuffer, int outBufferChars);

typedef _DestroyNative = ffi.Void Function(ffi.Int64 handle);
typedef _DestroyDart = void Function(int handle);

class _NativeCameraBindings {
  _NativeCameraBindings(ffi.DynamicLibrary lib)
      : start = lib.lookupFunction<_StartNative, _StartDart>('jyamiti_camera_start'),
        isFirstFrameReady = lib.lookupFunction<_HandleToIntNative, _HandleToIntDart>(
            'jyamiti_camera_is_first_frame_ready'),
        firstFrameUnixMicros = lib.lookupFunction<_HandleToInt64Native, _HandleToInt64Dart>(
            'jyamiti_camera_first_frame_unix_micros'),
        stop = lib.lookupFunction<_HandleToIntNative, _HandleToIntDart>('jyamiti_camera_stop'),
        lastError =
            lib.lookupFunction<_LastErrorNative, _LastErrorDart>('jyamiti_camera_last_error'),
        destroy = lib.lookupFunction<_DestroyNative, _DestroyDart>('jyamiti_camera_destroy');

  final _StartDart start;
  final _HandleToIntDart isFirstFrameReady;
  final _HandleToInt64Dart firstFrameUnixMicros;
  final _HandleToIntDart stop;
  final _LastErrorDart lastError;
  final _DestroyDart destroy;
}

_NativeCameraBindings? _bindings;

_NativeCameraBindings _loadBindings() {
  final _NativeCameraBindings? existing = _bindings;
  if (existing != null) return existing;
  final String exeDir = File(Platform.resolvedExecutable).parent.path;
  final ffi.DynamicLibrary lib =
      ffi.DynamicLibrary.open(p.join(exeDir, 'jyamiti_camera.dll'));
  final _NativeCameraBindings loaded = _NativeCameraBindings(lib);
  _bindings = loaded;
  return loaded;
}

/// Thin Dart wrapper around one native capture session (one `handle` in
/// the C ABI above). Each [start] call owns exactly one underlying
/// webcam-open -> encode -> finalize lifecycle; create a new instance per
/// recording, same as `MathPadRecordingService` does with its ffmpeg
/// `_cameraProcess`.
class NativeCameraCapture {
  NativeCameraCapture._(this._handle);

  final int _handle;
  bool _destroyed = false;

  /// Starts capturing from [deviceName] (must match a Media Foundation
  /// video capture device's friendly name exactly -- the same string
  /// `_detectCameraDeviceName()` already extracts from ffmpeg's dshow
  /// device list works here too, confirmed identical on real hardware)
  /// and encoding straight to H.264/MP4 at [outputPath].
  ///
  /// Throws [MathPadNativeCameraException] if the DLL can't be loaded at
  /// all (missing/corrupt install) -- callers should catch this the same
  /// way they already catch ffmpeg camera-spawn failures, and fall back
  /// to disabling the camera for the recording rather than aborting it.
  static NativeCameraCapture start(String deviceName, String outputPath) {
    final _NativeCameraBindings bindings = _loadBindings();
    final ffi.Pointer<ffi2.Utf16> nativeDevice = deviceName.toNativeUtf16();
    final ffi.Pointer<ffi2.Utf16> nativeOutput = outputPath.toNativeUtf16();
    try {
      final int handle = bindings.start(nativeDevice, nativeOutput);
      if (handle == 0) {
        throw MathPadNativeCameraException(
          'The native camera module rejected the request (invalid device or output path).',
        );
      }
      return NativeCameraCapture._(handle);
    } finally {
      ffi2.calloc.free(nativeDevice);
      ffi2.calloc.free(nativeOutput);
    }
  }

  /// True once the underlying worker thread has captured its first real
  /// frame and recorded a wall-clock timestamp for it. Never blocks --
  /// callers poll this (see its use in `MathPadRecordingService.start()`)
  /// rather than waiting on it, consistent with "camera trouble never
  /// blocks the recording" elsewhere in this codebase.
  bool get isFirstFrameReady => _loadBindings().isFirstFrameReady(_handle) != 0;

  /// The real wall-clock instant (microseconds since the Unix epoch,
  /// directly comparable to `DateTime.now()`) the first frame was
  /// captured at. Only meaningful once [isFirstFrameReady] is true.
  int get firstFrameUnixMicros => _loadBindings().firstFrameUnixMicros(_handle);

  /// Signals the capture thread to stop, finalizes the MP4, and blocks
  /// (on a background isolate-friendly native call -- still synchronous
  /// from Dart's perspective, so callers should `await` this via
  /// `Future(() => ...)`/an isolate if called from a latency-sensitive
  /// context) until fully done. Returns false if finalizing failed
  /// (output file may be missing/corrupt).
  bool stop() => _loadBindings().stop(_handle) != 0;

  /// The most recent failure message from the native module, if any.
  String? get lastError {
    final ffi.Pointer<ffi2.Utf16> buffer = ffi2.calloc<ffi.Uint16>(512).cast<ffi2.Utf16>();
    try {
      final int ok = _loadBindings().lastError(_handle, buffer, 512);
      if (ok == 0) return null;
      final String message = ffi2.Utf16Pointer(buffer).toDartString();
      return message.isEmpty ? null : message;
    } finally {
      ffi2.calloc.free(buffer);
    }
  }

  /// Releases native resources for this handle. Must be called exactly
  /// once, after [stop] has returned -- mirrors `_cameraProcess = null`
  /// after `_stopCameraCapture()` on the ffmpeg path.
  void dispose() {
    if (_destroyed) return;
    _destroyed = true;
    _loadBindings().destroy(_handle);
  }
}

class MathPadNativeCameraException implements Exception {
  MathPadNativeCameraException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ─── Native microphone capture (audio_capture.cpp) ─────────────────────
// Same DLL, same handle-based C ABI shape as the camera bindings above --
// see audio_capture.cpp's file-level doc comment for why this exists
// alongside the camera module.
typedef _AudioStartNative = ffi.Int64 Function(
    ffi.Pointer<ffi2.Utf16> outputPath, ffi.Int32 useRawCapture);
typedef _AudioStartDart = int Function(
    ffi.Pointer<ffi2.Utf16> outputPath, int useRawCapture);

class _NativeAudioBindings {
  _NativeAudioBindings(ffi.DynamicLibrary lib)
      : start = lib.lookupFunction<_AudioStartNative, _AudioStartDart>('jyamiti_audio_start'),
        isFirstFrameReady = lib.lookupFunction<_HandleToIntNative, _HandleToIntDart>(
            'jyamiti_audio_is_first_frame_ready'),
        firstFrameUnixMicros = lib.lookupFunction<_HandleToInt64Native, _HandleToInt64Dart>(
            'jyamiti_audio_first_frame_unix_micros'),
        stop = lib.lookupFunction<_HandleToIntNative, _HandleToIntDart>('jyamiti_audio_stop'),
        lastError =
            lib.lookupFunction<_LastErrorNative, _LastErrorDart>('jyamiti_audio_last_error'),
        destroy = lib.lookupFunction<_DestroyNative, _DestroyDart>('jyamiti_audio_destroy');

  final _AudioStartDart start;
  final _HandleToIntDart isFirstFrameReady;
  final _HandleToInt64Dart firstFrameUnixMicros;
  final _HandleToIntDart stop;
  final _LastErrorDart lastError;
  final _DestroyDart destroy;
}

_NativeAudioBindings? _audioBindings;

_NativeAudioBindings _loadAudioBindings() {
  final _NativeAudioBindings? existing = _audioBindings;
  if (existing != null) return existing;
  // Same DLL as the camera bindings -- `_loadBindings()`'s own
  // `DynamicLibrary.open()` call already caches the loaded library, so
  // this just needs its own `lookupFunction` calls against it, not a
  // second `open()`.
  final String exeDir = File(Platform.resolvedExecutable).parent.path;
  final ffi.DynamicLibrary lib =
      ffi.DynamicLibrary.open(p.join(exeDir, 'jyamiti_camera.dll'));
  final _NativeAudioBindings loaded = _NativeAudioBindings(lib);
  _audioBindings = loaded;
  return loaded;
}

/// Thin Dart wrapper around one native microphone capture session --
/// the audio-side equivalent of [NativeCameraCapture]. See
/// `audio_capture.cpp`'s doc comment for the full explanation.
class NativeAudioCapture {
  NativeAudioCapture._(this._handle);

  final int _handle;
  bool _destroyed = false;

  /// Starts capturing the default microphone straight to a WAV file at
  /// [outputPath], in whatever format the audio engine's own shared-mode
  /// mix format actually is (see the C++ file's doc comment for why that
  /// never needs to match what `record`-package capture produces).
  ///
  /// [useRawCapture] requests WASAPI bypass Windows' own microphone
  /// enhancement chain (noise suppression, AGC) -- see
  /// `MicEnhancementMode`'s doc comment in `mathpad_recording_service.dart`
  /// for what that trades off.
  static NativeAudioCapture start(String outputPath, {required bool useRawCapture}) {
    final _NativeAudioBindings bindings = _loadAudioBindings();
    final ffi.Pointer<ffi2.Utf16> nativeOutput = outputPath.toNativeUtf16();
    try {
      final int handle = bindings.start(nativeOutput, useRawCapture ? 1 : 0);
      if (handle == 0) {
        throw MathPadNativeCameraException(
          'The native audio module rejected the request (invalid output path).',
        );
      }
      return NativeAudioCapture._(handle);
    } finally {
      ffi2.calloc.free(nativeOutput);
    }
  }

  /// True once the worker thread has captured its first real audio
  /// packet and recorded a wall-clock timestamp for it. Never blocks --
  /// see [NativeCameraCapture.isFirstFrameReady]'s doc comment, same
  /// polling philosophy applies here.
  bool get isFirstFrameReady => _loadAudioBindings().isFirstFrameReady(_handle) != 0;

  /// The real wall-clock instant (microseconds since the Unix epoch)
  /// the first audio packet was captured at. Only meaningful once
  /// [isFirstFrameReady] is true.
  int get firstFrameUnixMicros => _loadAudioBindings().firstFrameUnixMicros(_handle);

  /// Stops capture and finalizes the WAV file's header. Synchronous --
  /// see [NativeCameraCapture.stop]'s doc comment, same tradeoff/caveat
  /// applies here (found fast in practice, not yet isolate-offloaded).
  bool stop() => _loadAudioBindings().stop(_handle) != 0;

  /// The most recent failure message from the native module, if any.
  String? get lastError {
    final ffi.Pointer<ffi2.Utf16> buffer = ffi2.calloc<ffi.Uint16>(512).cast<ffi2.Utf16>();
    try {
      final int ok = _loadAudioBindings().lastError(_handle, buffer, 512);
      if (ok == 0) return null;
      final String message = ffi2.Utf16Pointer(buffer).toDartString();
      return message.isEmpty ? null : message;
    } finally {
      ffi2.calloc.free(buffer);
    }
  }

  /// Releases native resources for this handle. Must be called exactly
  /// once, after [stop] has returned.
  void dispose() {
    if (_destroyed) return;
    _destroyed = true;
    _loadAudioBindings().destroy(_handle);
  }
}

// ─── Native "external compositor" (external_compositor.cpp) ────────────
// Same DLL, same handle-based C ABI shape as the camera/audio bindings
// above -- see external_compositor.cpp's file-level doc comment for why
// this exists: capturing this app's OWN window (Windows Graphics
// Capture), optionally compositing a live camera feed on top (Direct2D),
// and encoding the result (a piped ffmpeg process) all happen in this
// separate native module/thread, entirely outside Flutter's own
// rendering pipeline -- unlike CameraEncodeMode.onCanvas, which does the
// same live-compositing idea but ON Flutter's UI thread (confirmed via
// real testing to cause drawing lag/stutter).
typedef _CompositorStartNative = ffi.Int64 Function(
    ffi.Pointer<ffi2.Utf16> cameraDeviceName,
    ffi.Pointer<ffi2.Utf16> outputPath,
    ffi.Int32 fps,
    ffi.Int32 cropX,
    ffi.Int32 cropY,
    ffi.Int32 cropW,
    ffi.Int32 cropH);
typedef _CompositorStartDart = int Function(
    ffi.Pointer<ffi2.Utf16> cameraDeviceName,
    ffi.Pointer<ffi2.Utf16> outputPath,
    int fps,
    int cropX,
    int cropY,
    int cropW,
    int cropH);

typedef _CompositorSetCropNative = ffi.Int32 Function(
    ffi.Int64 handle, ffi.Int32 x, ffi.Int32 y, ffi.Int32 w, ffi.Int32 h);
typedef _CompositorSetCropDart = int Function(int handle, int x, int y, int w, int h);

class _NativeCompositorBindings {
  _NativeCompositorBindings(ffi.DynamicLibrary lib)
      : start = lib.lookupFunction<_CompositorStartNative, _CompositorStartDart>(
            'jyamiti_compositor_start'),
        setCrop = lib.lookupFunction<_CompositorSetCropNative, _CompositorSetCropDart>(
            'jyamiti_compositor_set_crop'),
        stop = lib.lookupFunction<_HandleToIntNative, _HandleToIntDart>('jyamiti_compositor_stop'),
        lastError = lib.lookupFunction<_LastErrorNative, _LastErrorDart>(
            'jyamiti_compositor_last_error'),
        destroy =
            lib.lookupFunction<_DestroyNative, _DestroyDart>('jyamiti_compositor_destroy');

  final _CompositorStartDart start;
  final _CompositorSetCropDart setCrop;
  final _HandleToIntDart stop;
  final _LastErrorDart lastError;
  final _DestroyDart destroy;
}

_NativeCompositorBindings? _compositorBindings;

_NativeCompositorBindings _loadCompositorBindings() {
  final _NativeCompositorBindings? existing = _compositorBindings;
  if (existing != null) return existing;
  final String exeDir = File(Platform.resolvedExecutable).parent.path;
  final ffi.DynamicLibrary lib =
      ffi.DynamicLibrary.open(p.join(exeDir, 'jyamiti_camera.dll'));
  final _NativeCompositorBindings loaded = _NativeCompositorBindings(lib);
  _compositorBindings = loaded;
  return loaded;
}

// ─── Linux backend (linux/native_camera/external_compositor.cc) ────────
// UNVERIFIED -- no Linux machine, no X11/GTK dev headers, no compiler was
// available to build or even syntax-check this. See that file's header
// comment for the full explanation and known risk areas (X11-only, no
// Wayland support; needs a compositing window manager running).
//
// Same C ABI shape and dart:ffi + shared-library pattern as the Windows
// backend above (unlike macOS, which uses a MethodChannel instead -- see
// that section's comment for why) -- but NOT the same typedefs, since the
// native signatures differ: Windows' C ABI takes `wchar_t*` (UTF-16, native
// Win32 string type) where Linux's takes plain `char*` (UTF-8, native
// POSIX string type). Same function names, different marshalling.
typedef _CompositorStartNativeLinux = ffi.Int64 Function(
    ffi.Pointer<ffi2.Utf8> cameraDevicePath,
    ffi.Pointer<ffi2.Utf8> outputPath,
    ffi.Int32 fps,
    ffi.Int32 cropX,
    ffi.Int32 cropY,
    ffi.Int32 cropW,
    ffi.Int32 cropH);
typedef _CompositorStartDartLinux = int Function(
    ffi.Pointer<ffi2.Utf8> cameraDevicePath,
    ffi.Pointer<ffi2.Utf8> outputPath,
    int fps,
    int cropX,
    int cropY,
    int cropW,
    int cropH);

typedef _LastErrorNativeLinux = ffi.Int32 Function(
    ffi.Int64 handle, ffi.Pointer<ffi2.Utf8> outBuffer, ffi.Int32 outBufferChars);
typedef _LastErrorDartLinux = int Function(
    int handle, ffi.Pointer<ffi2.Utf8> outBuffer, int outBufferChars);

class _NativeCompositorBindingsLinux {
  _NativeCompositorBindingsLinux(ffi.DynamicLibrary lib)
      : start = lib.lookupFunction<_CompositorStartNativeLinux, _CompositorStartDartLinux>(
            'jyamiti_compositor_start'),
        setCrop = lib.lookupFunction<_CompositorSetCropNative, _CompositorSetCropDart>(
            'jyamiti_compositor_set_crop'),
        stop = lib.lookupFunction<_HandleToIntNative, _HandleToIntDart>('jyamiti_compositor_stop'),
        lastError = lib.lookupFunction<_LastErrorNativeLinux, _LastErrorDartLinux>(
            'jyamiti_compositor_last_error'),
        destroy =
            lib.lookupFunction<_DestroyNative, _DestroyDart>('jyamiti_compositor_destroy');

  final _CompositorStartDartLinux start;
  final _CompositorSetCropDart setCrop;
  final _HandleToIntDart stop;
  final _LastErrorDartLinux lastError;
  final _DestroyDart destroy;
}

_NativeCompositorBindingsLinux? _compositorBindingsLinux;

_NativeCompositorBindingsLinux _loadCompositorBindingsLinux() {
  final _NativeCompositorBindingsLinux? existing = _compositorBindingsLinux;
  if (existing != null) return existing;
  final String exeDir = File(Platform.resolvedExecutable).parent.path;
  final ffi.DynamicLibrary lib =
      ffi.DynamicLibrary.open(p.join(exeDir, 'libjyamiti_camera.so'));
  final _NativeCompositorBindingsLinux loaded = _NativeCompositorBindingsLinux(lib);
  _compositorBindingsLinux = loaded;
  return loaded;
}

// ─── macOS backend (ExternalCompositor.swift, MainFlutterWindow.swift) ──
// UNVERIFIED -- written with no Mac/Xcode available to build or run it.
// See ExternalCompositor.swift's header comment for the full explanation
// and known risk areas. Uses a FlutterMethodChannel rather than dart:ffi
// (unlike the Windows backend above) -- a deliberate choice, not an
// inconsistency; see that same header comment for why.
//
// Also NOT currently reachable from the UI at all: MathPadRecordingService
// .start() still unconditionally throws on any non-Windows platform, so
// nothing below can actually run yet regardless of whether it's correct.
const MethodChannel _externalCompositorChannel = MethodChannel(
  'jyamiti.com/external_compositor',
);

/// Thin Dart wrapper around one native external-compositor session --
/// see `external_compositor.cpp`'s doc comment (Windows) and
/// `ExternalCompositor.swift`'s doc comment (macOS, UNVERIFIED) for the
/// full explanation. Unlike [NativeCameraCapture]/[NativeAudioCapture],
/// this has no first-frame-ready polling surface -- it's a fire-and-forget
/// capture+composite+encode session with no separate offset to measure
/// (there's only ever one stream here, camera baked directly into it if
/// present, so there's nothing to synchronize after the fact).
///
/// Every method here is `async`/returns a `Future` -- even on Windows,
/// where the underlying FFI calls are actually synchronous -- so callers
/// have one consistent API regardless of which native backend answers it
/// (macOS's MethodChannel calls are inherently async; forcing Windows's
/// synchronous FFI calls into the same Future-returning shape, rather
/// than giving each platform a different-shaped API, is what lets
/// `MathPadRecordingService` call this without ever branching on
/// platform itself).
enum _CompositorBackend { windows, linux, macOS }

class NativeExternalCompositor {
  NativeExternalCompositor._windows(this._handle) : _backend = _CompositorBackend.windows;
  NativeExternalCompositor._linux(this._handle) : _backend = _CompositorBackend.linux;
  NativeExternalCompositor._macOS()
      : _handle = 0,
        _backend = _CompositorBackend.macOS;

  final int _handle;
  final _CompositorBackend _backend;
  bool _destroyed = false;

  /// Starts capturing this app's own window (found internally by the
  /// native module -- no HWND/NSWindow needs to be passed from Dart),
  /// optionally compositing [cameraDeviceName]'s live feed on top (pass
  /// an empty string for window-capture-only, no camera), encoding
  /// continuously to [outputPath] at [fps].
  ///
  /// [cropRect], if given, is the canvas capture area's rectangle in
  /// physical-pixel window coordinates -- only that sub-region of the
  /// captured window gets encoded (at that rectangle's own size) instead
  /// of the full window/toolbar. Omit it (or pass null) to capture the
  /// full window, unchanged from before this existed. See [setCropRect]
  /// to update it live after the recording has started.
  static Future<NativeExternalCompositor> start({
    required String cameraDeviceName,
    required String outputPath,
    required int fps,
    Rectangle<int>? cropRect,
  }) async {
    if (Platform.isMacOS) {
      final bool? ok = await _externalCompositorChannel.invokeMethod<bool>('start', {
        'cameraDeviceName': cameraDeviceName,
        'outputPath': outputPath,
        'fps': fps,
        'cropX': cropRect?.left ?? 0,
        'cropY': cropRect?.top ?? 0,
        'cropW': cropRect?.width ?? 0,
        'cropH': cropRect?.height ?? 0,
      });
      if (ok != true) {
        throw MathPadNativeCameraException(
          'The native compositor module rejected the request.',
        );
      }
      return NativeExternalCompositor._macOS();
    }

    if (Platform.isLinux) {
      final _NativeCompositorBindingsLinux bindings = _loadCompositorBindingsLinux();
      final ffi.Pointer<ffi2.Utf8> nativeCameraName = cameraDeviceName.toNativeUtf8();
      final ffi.Pointer<ffi2.Utf8> nativeOutput = outputPath.toNativeUtf8();
      try {
        final int handle = bindings.start(
          nativeCameraName,
          nativeOutput,
          fps,
          cropRect?.left ?? 0,
          cropRect?.top ?? 0,
          cropRect?.width ?? 0,
          cropRect?.height ?? 0,
        );
        if (handle == 0) {
          throw MathPadNativeCameraException(
            'The native compositor module rejected the request (invalid output path).',
          );
        }
        return NativeExternalCompositor._linux(handle);
      } finally {
        ffi2.calloc.free(nativeCameraName);
        ffi2.calloc.free(nativeOutput);
      }
    }

    final _NativeCompositorBindings bindings = _loadCompositorBindings();
    final ffi.Pointer<ffi2.Utf16> nativeCameraName = cameraDeviceName.toNativeUtf16();
    final ffi.Pointer<ffi2.Utf16> nativeOutput = outputPath.toNativeUtf16();
    try {
      final int handle = bindings.start(
        nativeCameraName,
        nativeOutput,
        fps,
        cropRect?.left ?? 0,
        cropRect?.top ?? 0,
        cropRect?.width ?? 0,
        cropRect?.height ?? 0,
      );
      if (handle == 0) {
        throw MathPadNativeCameraException(
          'The native compositor module rejected the request (invalid output path).',
        );
      }
      return NativeExternalCompositor._windows(handle);
    } finally {
      ffi2.calloc.free(nativeCameraName);
      ffi2.calloc.free(nativeOutput);
    }
  }

  /// Updates which sub-rectangle of the captured window gets encoded,
  /// live, mid-recording -- e.g. after the canvas area moves/resizes
  /// (window resize, toolbar dock-side toggle). See
  /// `ExternalCompositor::SetCrop`'s doc comment (native side, both
  /// platforms) for what this does and doesn't affect (the output
  /// video's own dimensions are fixed at [start], never revisited here).
  /// Pass null to fall back to capturing the full window. Fire-and-forget
  /// is fine for callers -- a dropped/failed crop update just means the
  /// next tick's update (or the full window, if none ever lands) is used
  /// instead, never a fatal error.
  Future<void> setCropRect(Rectangle<int>? cropRect) async {
    if (_destroyed) return;
    if (_backend == _CompositorBackend.macOS) {
      await _externalCompositorChannel.invokeMethod<void>('setCrop', {
        'x': cropRect?.left ?? 0,
        'y': cropRect?.top ?? 0,
        'w': cropRect?.width ?? 0,
        'h': cropRect?.height ?? 0,
      });
      return;
    }
    final int x = cropRect?.left ?? 0;
    final int y = cropRect?.top ?? 0;
    final int w = cropRect?.width ?? 0;
    final int h = cropRect?.height ?? 0;
    if (_backend == _CompositorBackend.linux) {
      _loadCompositorBindingsLinux().setCrop(_handle, x, y, w, h);
      return;
    }
    _loadCompositorBindings().setCrop(_handle, x, y, w, h);
  }

  /// Stops capture, finalizes the video file, and waits until fully done.
  /// Returns false if finalizing failed (output file may be
  /// missing/corrupt, e.g. the app's own window couldn't be found or the
  /// encoder process died).
  Future<bool> stop() async {
    switch (_backend) {
      case _CompositorBackend.macOS:
        final bool? ok = await _externalCompositorChannel.invokeMethod<bool>('stop');
        return ok ?? false;
      case _CompositorBackend.linux:
        return _loadCompositorBindingsLinux().stop(_handle) != 0;
      case _CompositorBackend.windows:
        return _loadCompositorBindings().stop(_handle) != 0;
    }
  }

  /// The most recent failure message from the native module, if any.
  Future<String?> get lastError async {
    switch (_backend) {
      case _CompositorBackend.macOS:
        return _externalCompositorChannel.invokeMethod<String?>('lastError');
      case _CompositorBackend.linux:
        final ffi.Pointer<ffi2.Utf8> buffer = ffi2.calloc<ffi.Uint8>(512).cast<ffi2.Utf8>();
        try {
          final int ok = _loadCompositorBindingsLinux().lastError(_handle, buffer, 512);
          if (ok == 0) return null;
          final String message = buffer.toDartString();
          return message.isEmpty ? null : message;
        } finally {
          ffi2.calloc.free(buffer);
        }
      case _CompositorBackend.windows:
        final ffi.Pointer<ffi2.Utf16> buffer = ffi2.calloc<ffi.Uint16>(512).cast<ffi2.Utf16>();
        try {
          final int ok = _loadCompositorBindings().lastError(_handle, buffer, 512);
          if (ok == 0) return null;
          final String message = ffi2.Utf16Pointer(buffer).toDartString();
          return message.isEmpty ? null : message;
        } finally {
          ffi2.calloc.free(buffer);
        }
    }
  }

  /// Releases native resources for this handle. Must be called exactly
  /// once, after [stop] has returned. A no-op on macOS -- there's no
  /// persistent native handle table there the way Windows/Linux have one
  /// (`stop` already fully tears down that session's native state), only
  /// this Dart-side wrapper needs marking as spent.
  void dispose() {
    if (_destroyed) return;
    _destroyed = true;
    switch (_backend) {
      case _CompositorBackend.macOS:
        return;
      case _CompositorBackend.linux:
        _loadCompositorBindingsLinux().destroy(_handle);
        return;
      case _CompositorBackend.windows:
        _loadCompositorBindings().destroy(_handle);
        return;
    }
  }
}
