import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as ffi2;
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
