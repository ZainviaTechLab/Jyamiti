// Conditional-import barrel -- picks the real package:web/dart:js_interop
// -based implementation (mathpad_web_recording_service_web.dart) on web,
// and a stub (mathpad_web_recording_service_stub.dart) on every platform
// where dart:io is available instead. Same public API either way
// (MathPadWebRecordingService, MathPadWebRecordingException) -- mathpad.dart
// imports this file, never the platform-specific ones directly, and gates
// actual use on `kIsWeb` itself (the stub only exists so the import/class
// references compile everywhere; it's never actually reached).
export 'mathpad_web_recording_service_web.dart'
    if (dart.library.io) 'mathpad_web_recording_service_stub.dart';
