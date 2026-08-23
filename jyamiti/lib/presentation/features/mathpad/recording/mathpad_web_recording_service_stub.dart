// Non-web stub for mathpad_web_recording_service_web.dart -- see
// mathpad_web_recording_service.dart (the barrel) for which one actually
// gets picked. Never reachable at runtime: mathpad.dart only ever
// instantiates/calls MathPadWebRecordingService behind a `kIsWeb` check,
// same as every other web-only feature in this app. Exists purely so
// mathpad.dart can import one set of class names unconditionally without
// pulling package:web/dart:js_interop into the Windows/macOS/Linux/
// Android/iOS builds at all.

class MathPadWebRecordingException implements Exception {
  MathPadWebRecordingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MathPadWebRecordingService {
  bool get isRecording => false;

  Future<void> start({int fps = 30}) async {
    throw MathPadWebRecordingException(
      'Web recording is not available on this platform.',
    );
  }

  Future<void> stopAndDownload({String filenameWithoutExtension = 'MathPad_recording'}) async {
    throw MathPadWebRecordingException('Not currently recording.');
  }
}
