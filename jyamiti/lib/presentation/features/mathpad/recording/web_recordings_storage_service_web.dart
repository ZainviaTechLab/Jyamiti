// Web equivalent of desktop recordings list -- uses native browser IndexedDB
// directly with native Blob storage so saving, listing, and playback are
// instantaneous with zero main-thread JSON serialization lag.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_recording_meta.dart';

const String _dbName = 'jyamiti_mathpad_web_recordings_v2';
const int _dbVersion = 1;
const String _metaStoreName = 'recording_meta';
const String _blobStoreName = 'recording_blobs';

extension type _RecordingMetaRecord._(JSObject _) implements JSObject {
  external factory _RecordingMetaRecord({
    String id,
    String name,
    String mimeType,
    int sizeBytes,
    int createdAtMillis,
  });

  external JSString? get id;
  external JSString? get name;
  external JSString? get mimeType;
  external JSNumber? get sizeBytes;
  external JSNumber? get createdAtMillis;
}

class MathPadWebRecordingsStorageService {
  web.IDBDatabase? _idb;

  Future<web.IDBDatabase> _openDb() async {
    final existing = _idb;
    if (existing != null) return existing;

    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, _dbVersion);

    request.onupgradeneeded = ((web.IDBVersionChangeEvent event) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_metaStoreName)) {
        db.createObjectStore(_metaStoreName);
      }
      if (!db.objectStoreNames.contains(_blobStoreName)) {
        db.createObjectStore(_blobStoreName);
      }
    }).toJS;

    request.onsuccess = ((web.Event event) {
      final db = request.result as web.IDBDatabase;
      _idb = db;
      completer.complete(db);
    }).toJS;

    request.onerror = ((web.Event event) {
      completer.completeError(
        'Failed to open IndexedDB: ${request.error?.message}',
      );
    }).toJS;

    try {
      unawaited(web.window.navigator.storage.persist().toDart);
    } catch (_) {}

    return completer.future;
  }

  /// Saves a recording into native IndexedDB.
  /// Stores binary data directly as a native browser Blob without any
  /// CPU-heavy JSON serialization so it finishes in milliseconds.
  Future<void> saveRecording({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final db = await _openDb();
    final String id = DateTime.now().microsecondsSinceEpoch.toString();
    final int nowMillis = DateTime.now().millisecondsSinceEpoch;

    final txn = db.transaction(
      [_metaStoreName.toJS, _blobStoreName.toJS].toJS,
      'readwrite',
    );
    final metaStore = txn.objectStore(_metaStoreName);
    final blobStore = txn.objectStore(_blobStoreName);

    final metaRecord = _RecordingMetaRecord(
      id: id,
      name: name,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      createdAtMillis: nowMillis,
    );

    final web.Blob blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );

    metaStore.put(metaRecord, id.toJS);
    blobStore.put(blob, id.toJS);

    final completer = Completer<void>();
    txn.oncomplete = ((web.Event _) {
      completer.complete();
    }).toJS;
    txn.onerror = ((web.Event _) {
      completer.completeError('Failed to save recording');
    }).toJS;
    await completer.future;
  }

  Future<List<WebRecordingMeta>> listRecordings() async {
    try {
      final db = await _openDb();
      final txn = db.transaction([_metaStoreName.toJS].toJS, 'readonly');
      final metaStore = txn.objectStore(_metaStoreName);
      final request = metaStore.getAll();

      final completer = Completer<List<WebRecordingMeta>>();
      request.onsuccess = ((web.Event _) {
        final JSArray? results = request.result as JSArray?;
        if (results == null) {
          completer.complete([]);
          return;
        }
        final list = <WebRecordingMeta>[];
        final dartList = results.toDart;
        for (final item in dartList) {
          if (item.isA<JSObject>()) {
            final meta = _RecordingMetaRecord._(item as JSObject);
            final id = meta.id?.toDart ?? '';
            final name = meta.name?.toDart ?? 'Recording';
            final mimeType = meta.mimeType?.toDart ?? 'video/webm';
            final sizeBytes = meta.sizeBytes?.toDartInt ?? 0;
            final createdAtMillis = meta.createdAtMillis?.toDartInt ?? 0;
            list.add(
              WebRecordingMeta(
                id: id,
                name: name,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                createdAt:
                    DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
              ),
            );
          }
        }
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        completer.complete(list);
      }).toJS;

      request.onerror = ((web.Event _) {
        completer.complete([]);
      }).toJS;
      return completer.future;
    } catch (_) {
      return [];
    }
  }

  Future<Uint8List?> loadRecordingBytes(String id) async {
    try {
      final db = await _openDb();
      final txn = db.transaction([_blobStoreName.toJS].toJS, 'readonly');
      final blobStore = txn.objectStore(_blobStoreName);
      final request = blobStore.get(id.toJS);

      final completer = Completer<Uint8List?>();
      request.onsuccess = ((web.Event _) {
        final result = request.result;
        if (result == null) {
          completer.complete(null);
          return;
        }
        if (result.isA<web.Blob>()) {
          final blob = result as web.Blob;
          unawaited(() async {
            try {
              final JSArrayBuffer arrayBuffer =
                  await blob.arrayBuffer().toDart;
              completer.complete(arrayBuffer.toDart.asUint8List());
            } catch (_) {
              completer.complete(null);
            }
          }());
        } else if (result.isA<JSArrayBuffer>()) {
          final buffer = result as JSArrayBuffer;
          completer.complete(buffer.toDart.asUint8List());
        } else {
          completer.complete(null);
        }
      }).toJS;

      request.onerror = ((web.Event _) {
        completer.complete(null);
      }).toJS;
      return completer.future;
    } catch (_) {
      return null;
    }
  }

  Future<bool> downloadRecording(String id, String filename) async {
    try {
      final db = await _openDb();
      final txn = db.transaction([_blobStoreName.toJS].toJS, 'readonly');
      final blobStore = txn.objectStore(_blobStoreName);
      final request = blobStore.get(id.toJS);

      final completer = Completer<bool>();
      request.onsuccess = ((web.Event _) {
        final result = request.result;
        if (result == null) {
          completer.complete(false);
          return;
        }
        web.Blob blob;
        if (result.isA<web.Blob>()) {
          blob = result as web.Blob;
        } else if (result.isA<JSArrayBuffer>()) {
          blob = web.Blob([result as JSArrayBuffer].toJS);
        } else {
          completer.complete(false);
          return;
        }

        final String url = web.URL.createObjectURL(blob);
        final web.HTMLAnchorElement anchor = web.HTMLAnchorElement()
          ..href = url
          ..download = filename
          ..style.display = 'none';
        web.document.body?.append(anchor);
        anchor.click();
        anchor.remove();
        web.URL.revokeObjectURL(url);
        completer.complete(true);
      }).toJS;

      request.onerror = ((web.Event _) {
        completer.complete(false);
      }).toJS;
      return completer.future;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteRecording(String id) async {
    try {
      final db = await _openDb();
      final txn = db.transaction(
        [_metaStoreName.toJS, _blobStoreName.toJS].toJS,
        'readwrite',
      );
      txn.objectStore(_metaStoreName).delete(id.toJS);
      txn.objectStore(_blobStoreName).delete(id.toJS);
    } catch (_) {}
  }

  /// Creates a temporary Blob Object URL for playing the recording in an HTML video element.
  Future<String?> getRecordingBlobUrl(String id) async {
    try {
      final db = await _openDb();
      final txn = db.transaction([_blobStoreName.toJS].toJS, 'readonly');
      final blobStore = txn.objectStore(_blobStoreName);
      final request = blobStore.get(id.toJS);

      final completer = Completer<String?>();
      request.onsuccess = ((web.Event _) {
        final result = request.result;
        if (result == null) {
          completer.complete(null);
          return;
        }
        if (result.isA<web.Blob>()) {
          final url = web.URL.createObjectURL(result as web.Blob);
          completer.complete(url);
        } else if (result.isA<JSArrayBuffer>()) {
          final blob = web.Blob([result as JSArrayBuffer].toJS);
          final url = web.URL.createObjectURL(blob);
          completer.complete(url);
        } else {
          completer.complete(null);
        }
      }).toJS;

      request.onerror = ((web.Event _) {
        completer.complete(null);
      }).toJS;
      return completer.future;
    } catch (_) {
      return null;
    }
  }

  /// Revokes a previously created Blob Object URL to free browser memory.
  void revokeBlobUrl(String url) {
    try {
      web.URL.revokeObjectURL(url);
    } catch (_) {}
  }
}
