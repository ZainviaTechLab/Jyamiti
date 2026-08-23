// Web stub for camera_capture_native_io.dart -- see camera_capture_native
// .dart (the barrel) for which one actually gets picked. None of this is
// reachable at runtime today -- MathPadRecordingService.start() still
// throws on any non-Windows platform, recording isn't wired up for web at
// all yet -- this file exists purely so mathpad_recording_service.dart can
// import one set of class names unconditionally without pulling
// dart:ffi/package:ffi (which don't compile for web) into the web build.
//
// Every `start()` below throws immediately, exactly like a real native
// camera/compositor failure already does on the other platforms -- every
// call site already wraps these in a try/catch as part of this app's
// established "camera trouble costs the camera, never the recording"
// philosophy, so this is a safe, consistent way for a web build to behave
// if any of this were ever (incorrectly) reached.

import 'dart:math';

class MathPadNativeCameraException implements Exception {
  MathPadNativeCameraException(this.message);
  final String message;
  @override
  String toString() => message;
}

class NativeCameraCapture {
  NativeCameraCapture._();

  static NativeCameraCapture start(String deviceName, String outputPath) {
    throw MathPadNativeCameraException(
      'Native camera capture is not available on web.',
    );
  }

  bool get isFirstFrameReady => false;
  int get firstFrameUnixMicros => 0;
  bool stop() => false;
  String? get lastError => null;
  void dispose() {}
}

class NativeAudioCapture {
  NativeAudioCapture._();

  static NativeAudioCapture start(String outputPath, {required bool useRawCapture}) {
    throw MathPadNativeCameraException(
      'Native audio capture is not available on web.',
    );
  }

  bool get isFirstFrameReady => false;
  int get firstFrameUnixMicros => 0;
  bool stop() => false;
  String? get lastError => null;
  void dispose() {}
}

class NativeExternalCompositor {
  NativeExternalCompositor._();

  static Future<NativeExternalCompositor> start({
    required String cameraDeviceName,
    required String outputPath,
    required int fps,
    Rectangle<int>? cropRect,
  }) async {
    throw MathPadNativeCameraException(
      'The native external compositor is not available on web -- see '
      'MathPadWebRecordingService for the actual web recording path.',
    );
  }

  Future<void> setCropRect(Rectangle<int>? cropRect) async {}
  Future<bool> stop() async => false;
  Future<String?> get lastError async => null;
  void dispose() {}
}
