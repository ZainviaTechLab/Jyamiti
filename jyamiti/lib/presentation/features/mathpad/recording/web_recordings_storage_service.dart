// Conditional-import barrel -- picks the real IndexedDB-backed
// implementation (web_recordings_storage_service_web.dart) on web, and a
// stub (web_recordings_storage_service_io.dart) on every platform where
// dart:io is available instead. This is a web-only CONCEPT (desktop/mobile
// already have their own, entirely separate file-based recordings list --
// see TutorRecordingsScreen/MathPadRecordingService.getRecordings) so the
// stub is never actually reached; it exists purely so files that need to
// list web recordings can import one set of names unconditionally, same
// reason every other web-specific service in this app got the same
// treatment. See web_recording_meta.dart for WebRecordingMeta -- kept in
// its own leaf file rather than here so neither platform variant needs to
// import this barrel back (would be circular).
export 'web_recording_meta.dart';
export 'web_recordings_storage_service_web.dart'
    if (dart.library.io) 'web_recordings_storage_service_io.dart';
