// Web equivalent of mathpad_library_storage_service_io.dart -- same public
// API (MathPadLibraryStorageService, MathPadLastWorked), backed by
// IndexedDB (via sembast_web) instead of File/Directory, which don't exist
// on web at all. Picked automatically by mathpad_library_storage_service
// .dart (the barrel); callers never branch on platform themselves.
//
// UNVERIFIED IN AN ACTUAL BROWSER, but compile-checked for real: unlike the
// native compositor ports, this is pure Dart, so `flutter build web`
// actually type-checks the sembast_web API usage here -- what it can't
// confirm is real IndexedDB runtime behavior (storage quota, eviction,
// actual persistence across reloads), which needs a real browser to see.
//
// SCHEMA (four sembast stores, all keyed/queryable by plain string fields
// -- see each store's own comment below for why):
//   library_index  -- key: batchId                    -> index JSON map
//   pages          -- key: "$batchId:$pageId"          -> page JSON map
//                                                          (no image bytes --
//                                                          see page_images)
//   page_images    -- key: "$batchId:$pageId:$path"    -> {batchId, pageId,
//                                                          relativePath, bytes}
//   thumbnails     -- key: "$batchId:$pageId"           -> {bytes}
//
// Real risks specific to this, not present in the file-based version (see
// the design discussion that led here):
//   - Browsers can evict IndexedDB data under storage pressure (Safari
//     especially) unless the origin has persistent storage granted --
//     `_ensureDb` requests it once, best-effort, but that's a request, not
//     a guarantee.
//   - No cross-device/browser portability at all -- clearing site data or
//     switching browsers loses everything, with less recourse than a file
//     could at least in principle offer.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sembast_web/sembast_web.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import '../models/mathpad_library_models.dart';
import '../models/page_snapshot.dart';

typedef MathPadLastWorked = ({String batchId, String nodeId, String pageId});

const String _lastWorkedPrefsKey = 'jyamiti_mathpad_last_worked';
const String _dbName = 'jyamiti_mathpad_library.db';

final StoreRef<String, Map<String, dynamic>> _indexStore =
    stringMapStoreFactory.store('library_index');
final StoreRef<String, Map<String, dynamic>> _pageStore =
    stringMapStoreFactory.store('pages');
final StoreRef<String, Map<String, dynamic>> _pageImagesStore =
    stringMapStoreFactory.store('page_images');
final StoreRef<String, Map<String, dynamic>> _thumbnailStore =
    stringMapStoreFactory.store('thumbnails');

class MathPadLibraryStorageService {
  Database? _db;
  bool _persistRequested = false;

  Future<Database> _ensureDb() async {
    final Database? existing = _db;
    if (existing != null) return existing;
    final Database opened = await databaseFactoryWeb.openDatabase(_dbName);
    _db = opened;

    // Best-effort, once per app run -- see this file's header comment.
    // Never allowed to block or fail actual storage operations; a browser
    // that ignores/ doesn't support this request just keeps its default
    // eviction behavior, same as if this call didn't exist.
    if (!_persistRequested) {
      _persistRequested = true;
      try {
        await web.window.navigator.storage.persist().toDart;
      } catch (_) {}
    }
    return opened;
  }

  String _pageKey(String batchId, String pageId) => '$batchId:$pageId';
  String _imageKey(String batchId, String pageId, String relativePath) =>
      '$batchId:$pageId:$relativePath';

  Future<MathPadLibraryIndex> loadOrSeedIndex(
    String batchId, {
    required String batchCourseName,
    String? courseId,
    List<dynamic>? courseSyllabus,
  }) async {
    final Database db = await _ensureDb();
    final Map<String, dynamic>? existing = await _indexStore.record(batchId).get(db);
    if (existing != null) {
      return MathPadLibraryIndex.fromJson(existing);
    }

    final MathPadBook defaultBook = MathPadBook.create(
      batchCourseName,
      isDefault: true,
      sourceCourseId: courseId,
    );
    for (final rawChapter in (courseSyllabus ?? [])) {
      final chapterMap = rawChapter as Map<String, dynamic>;
      final chapter = defaultBook.addChapter(chapterMap['title'] as String? ?? 'Untitled Chapter');
      for (final rawTopic in (chapterMap['topics'] as List? ?? [])) {
        final topicMap = rawTopic as Map<String, dynamic>;
        final topic = chapter.addTopic(topicMap['title'] as String? ?? 'Untitled Topic');
        for (final rawSubTopic in (topicMap['subTopics'] as List? ?? [])) {
          final subTopicMap = rawSubTopic as Map<String, dynamic>;
          topic.addSubTopic(subTopicMap['title'] as String? ?? 'Untitled Sub-topic');
        }
      }
    }

    final MathPadLibraryIndex index = MathPadLibraryIndex(batchId: batchId, books: [defaultBook]);
    await saveIndex(batchId, index);
    return index;
  }

  /// IndexedDB writes are atomic per-transaction already -- no manual
  /// tmp-then-rename dance needed the way the file-based version does.
  Future<void> saveIndex(String batchId, MathPadLibraryIndex index) async {
    final Database db = await _ensureDb();
    await _indexStore.record(batchId).put(db, index.toJson());
  }

  Future<MathPadPageSnapshot> loadPage(String batchId, String pageId) async {
    final Database db = await _ensureDb();
    final Map<String, dynamic>? json =
        await _pageStore.record(_pageKey(batchId, pageId)).get(db);
    if (json == null) return MathPadPageSnapshot.empty();

    return decodePageSnapshot(
      json,
      readImageBytes: (relativePath) async {
        final Map<String, dynamic>? imageRecord =
            await _pageImagesStore.record(_imageKey(batchId, pageId, relativePath)).get(db);
        final Object? bytes = imageRecord?['bytes'];
        return bytes is Uint8List ? bytes : null;
      },
    );
  }

  /// Full-overwrite-per-save, same as the file-based version: replaces the
  /// page record and every image record for this page in one atomic
  /// transaction, which also naturally garbage-collects images left over
  /// from strokes edited/deleted since the last save.
  Future<void> savePage(String batchId, String pageId, MathPadPageSnapshot snapshot) async {
    final Database db = await _ensureDb();
    final List<MapEntry<String, Uint8List>> pendingImages = [];

    final Map<String, dynamic> json = await encodePageSnapshot(
      snapshot,
      writeImageBytes: (relativePath, pngBytes) async {
        pendingImages.add(MapEntry(relativePath, pngBytes));
      },
    );

    await db.transaction((txn) async {
      // Clear every existing image for this page first -- same
      // full-overwrite/garbage-collection semantics as the file-based
      // version's images_tmp-then-rename swap.
      await _pageImagesStore.delete(
        txn,
        finder: Finder(
          filter: Filter.and([
            Filter.equals('batchId', batchId),
            Filter.equals('pageId', pageId),
          ]),
        ),
      );
      for (final entry in pendingImages) {
        await _pageImagesStore.record(_imageKey(batchId, pageId, entry.key)).put(txn, {
          'batchId': batchId,
          'pageId': pageId,
          'relativePath': entry.key,
          'bytes': entry.value,
        });
      }
      await _pageStore.record(_pageKey(batchId, pageId)).put(txn, json);
    });
  }

  Future<void> saveThumbnail(String batchId, String pageId, Uint8List pngBytes) async {
    final Database db = await _ensureDb();
    await _thumbnailStore.record(_pageKey(batchId, pageId)).put(db, {'bytes': pngBytes});
  }

  Future<Uint8List?> loadThumbnail(String batchId, String pageId) async {
    final Database db = await _ensureDb();
    final Map<String, dynamic>? record =
        await _thumbnailStore.record(_pageKey(batchId, pageId)).get(db);
    final Object? bytes = record?['bytes'];
    return bytes is Uint8List ? bytes : null;
  }

  Future<void> deletePages(String batchId, List<String> pageIds) async {
    final Database db = await _ensureDb();
    await db.transaction((txn) async {
      for (final pageId in pageIds) {
        await _pageStore.record(_pageKey(batchId, pageId)).delete(txn);
        await _thumbnailStore.record(_pageKey(batchId, pageId)).delete(txn);
        await _pageImagesStore.delete(
          txn,
          finder: Finder(
            filter: Filter.and([
              Filter.equals('batchId', batchId),
              Filter.equals('pageId', pageId),
            ]),
          ),
        );
      }
    });
  }

  /// Unlike everything above, this already worked on web before today --
  /// `shared_preferences` has a real (localStorage-backed) web
  /// implementation. Kept here verbatim (not delegated to a shared file)
  /// since it's the exact same handful of lines as the io version and
  /// genuinely never diverges between them.
  Future<void> saveLastWorked(MathPadLastWorked location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastWorkedPrefsKey,
      jsonEncode({
        'batchId': location.batchId,
        'nodeId': location.nodeId,
        'pageId': location.pageId,
      }),
    );
  }

  Future<MathPadLastWorked?> loadLastWorked() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_lastWorkedPrefsKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final batchId = json['batchId'] as String?;
      final nodeId = json['nodeId'] as String?;
      final pageId = json['pageId'] as String?;
      if (batchId == null || nodeId == null || pageId == null) return null;
      return (batchId: batchId, nodeId: nodeId, pageId: pageId);
    } catch (_) {
      return null;
    }
  }
}
