// Web equivalent of the desktop's file-based recordings list
// (TutorRecordingsScreen/MathPadRecordingService.getRecordings) -- there's
// no shared interface between them (unlike MathPadLibraryStorageService's
// io/web split) since the two UIs are different enough (Drive/YouTube/
// WhatsApp share, "Play" via a native file path -- none of which map to
// web the same way) that a shared screen wasn't worth building. This is
// purely a place for MathPadWebRecordingService's output to land instead
// of an automatic download -- see that file's `stop()` doc comment.
//
// Same IndexedDB-via-sembast_web approach as
// mathpad_library_storage_service_web.dart, and the same two-store split
// for the same reason: metadata (name/mimeType/size/date) lives in its own
// store so listing recordings never has to pay for loading every
// recording's full video bytes just to show a list -- those live in a
// separate store, keyed the same way, fetched only when a tutor actually
// taps Download.
//
// UNVERIFIED IN THE BROWSER, but compile-checked: `flutter build web`
// checks this file's package:web/sembast_web usage for real.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sembast_web/sembast_web.dart';
import 'package:web/web.dart' as web;

import 'web_recording_meta.dart';

const String _dbName = 'jyamiti_mathpad_web_recordings.db';

final StoreRef<String, Map<String, dynamic>> _metaStore =
    stringMapStoreFactory.store('recording_meta');
final StoreRef<String, Map<String, dynamic>> _bytesStore =
    stringMapStoreFactory.store('recording_bytes');

class MathPadWebRecordingsStorageService {
  Database? _db;

  Future<Database> _ensureDb() async {
    final Database? existing = _db;
    if (existing != null) return existing;
    final Database opened = await databaseFactoryWeb.openDatabase(_dbName);
    _db = opened;
    // Best-effort, same reasoning/caveats as
    // MathPadLibraryStorageService_web's identical call -- never allowed
    // to block or fail actual storage operations.
    try {
      await web.window.navigator.storage.persist().toDart;
    } catch (_) {}
    return opened;
  }

  Future<void> saveRecording({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final Database db = await _ensureDb();
    final String id = DateTime.now().microsecondsSinceEpoch.toString();
    await db.transaction((txn) async {
      await _metaStore.record(id).put(txn, {
        'name': name,
        'mimeType': mimeType,
        'sizeBytes': bytes.length,
        'createdAtMillis': DateTime.now().millisecondsSinceEpoch,
      });
      await _bytesStore.record(id).put(txn, {'bytes': bytes});
    });
  }

  Future<List<WebRecordingMeta>> listRecordings() async {
    final Database db = await _ensureDb();
    final List<RecordSnapshot<String, Map<String, dynamic>>> records =
        await _metaStore.find(db);
    final List<WebRecordingMeta> result = records.map((record) {
      final Map<String, dynamic> value = record.value;
      return WebRecordingMeta(
        id: record.key,
        name: value['name'] as String? ?? 'Recording',
        mimeType: value['mimeType'] as String? ?? 'video/webm',
        sizeBytes: value['sizeBytes'] as int? ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          value['createdAtMillis'] as int? ?? 0,
        ),
      );
    }).toList();
    // Newest first -- matches the desktop recordings list's own ordering
    // (TutorRecordingsScreen sorts by lastModifiedSync descending).
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<Uint8List?> loadRecordingBytes(String id) async {
    final Database db = await _ensureDb();
    final Map<String, dynamic>? record = await _bytesStore.record(id).get(db);
    final Object? bytes = record?['bytes'];
    return bytes is Uint8List ? bytes : null;
  }

  /// Loads [id]'s bytes and triggers a browser download of them as
  /// [filename] -- kept here (not in the recording screen itself) so
  /// every `package:web` reference for this feature stays behind this
  /// file's conditional-import barrel; the screen that calls this never
  /// needs to import `package:web` at all. Returns false if [id] has no
  /// stored bytes (e.g. already deleted).
  Future<bool> downloadRecording(String id, String filename) async {
    final Database db = await _ensureDb();
    final Map<String, dynamic>? bytesRecord = await _bytesStore.record(id).get(db);
    final Object? rawBytes = bytesRecord?['bytes'];
    if (rawBytes is! Uint8List) return false;
    final Uint8List bytes = rawBytes;
    final Map<String, dynamic>? meta = await _metaStore.record(id).get(db);
    final String mimeType = meta?['mimeType'] as String? ?? 'video/webm';
    final web.Blob blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final String url = web.URL.createObjectURL(blob);
    final web.HTMLAnchorElement anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return true;
  }

  Future<void> deleteRecording(String id) async {
    final Database db = await _ensureDb();
    await db.transaction((txn) async {
      await _metaStore.record(id).delete(txn);
      await _bytesStore.record(id).delete(txn);
    });
  }
}
