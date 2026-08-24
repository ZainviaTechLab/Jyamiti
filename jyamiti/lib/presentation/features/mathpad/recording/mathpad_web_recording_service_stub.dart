// Non-web stub for mathpad_web_recording_service_web.dart -- see
// mathpad_web_recording_service.dart (the barrel) for which one actually
// gets picked. Never reachable at runtime: mathpad.dart only ever
// instantiates/calls MathPadWebRecordingService behind a `kIsWeb` check,
// same as every other web-only feature in this app. Exists purely so
// mathpad.dart can import one set of class names unconditionally without
// pulling package:web/dart:js_interop into the Windows/macOS/Linux/
// Android/iOS builds at all.

import 'dart:ui' as ui;

import 'mathpad_web_recording_result.dart';
import 'mathpad_web_recording_service.dart';

class MathPadWebRecordingException implements Exception {
  MathPadWebRecordingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MathPadWebRecordingService {
  static final MathPadWebRecordingService _instance = MathPadWebRecordingService();
  static MathPadWebRecordingService get instance => _instance;

  bool get isRecording => false;
  bool get isCameraActive => false;
  Duration get elapsed => Duration.zero;

  void updateCaptureCanvasFrame(
    Future<ui.Image?> Function({bool forceRefresh})? callback,
  ) {}

  Future<void> start({
    int fps = 30,
    bool includeCamera = false,
    WebRecordingTarget target = WebRecordingTarget.canvasOnly,
    Future<ui.Image?> Function({bool forceRefresh})? captureCanvasFrame,
  }) async {
    throw MathPadWebRecordingException(
      'Web recording is not available on this platform.',
    );
  }

  Future<MathPadWebRecordingResult> stop() async {
    throw MathPadWebRecordingException('Not currently recording.');
  }

  void cancelSync() {}
}
