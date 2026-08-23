// Web stub for job_object_lifetime_io.dart -- see job_object_lifetime.dart
// for which one actually gets picked. Recording itself isn't reachable on
// web at all yet (MathPadRecordingService.start() still throws on any
// non-Windows platform), so this never actually runs today -- it exists so
// mathpad_recording_service.dart can import ONE name unconditionally
// without pulling dart:ffi/win32 (which don't compile for web -- see the
// io file's doc comment) into the web build at all.
void tieProcessLifetimeToApp(int pid) {}
