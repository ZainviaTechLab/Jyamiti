// Non-web stub for web_recordings_storage_service_web.dart -- see
// web_recordings_storage_service.dart (the barrel) for which one actually
// gets picked. Never reachable at runtime: every caller only ever touches
// this behind a `kIsWeb` check (the web recordings LIST screen itself is
// only ever shown on web -- desktop/mobile have their own, separate,
// file-based recordings list, see TutorRecordingsScreen). Exists purely so
// files that import this barrel can compile unconditionally without
// pulling package:web/sembast_web into the Windows/macOS/Linux/Android/iOS
// builds at all.

import 'dart:typed_data';

import 'web_recording_meta.dart';

class MathPadWebRecordingsStorageService {
  Future<void> saveRecording({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {}

  Future<List<WebRecordingMeta>> listRecordings() async => const [];

  Future<Uint8List?> loadRecordingBytes(String id) async => null;

  Future<bool> downloadRecording(String id, String filename) async => false;

  Future<void> deleteRecording(String id) async {}

  Future<String?> getRecordingBlobUrl(String id) async => null;

  void revokeBlobUrl(String url) {}
}
