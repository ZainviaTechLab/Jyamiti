// Renamed from mathpad_library_storage_service.dart -- imported
// conditionally now (see mathpad_library_storage_service.dart, the new
// barrel file) rather than directly, because `dart:io`'s File/Directory
// don't exist on web at all. mathpad_library_storage_service_web.dart is
// the IndexedDB-backed (sembast_web) web equivalent, same public API.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mathpad_library_models.dart';
import '../models/page_snapshot.dart';

/// Where the tutor was last actively working -- resolved back into a real
/// node/page by `MathPadLibraryScreen` on next entry so Math Pad can open
/// directly into the pad instead of always showing the browser first.
typedef MathPadLastWorked = ({String batchId, String nodeId, String pageId});

const String _lastWorkedPrefsKey = 'jyamiti_mathpad_last_worked';

/// On-device (no backend sync) persistence for the Math Pad library:
/// one Book -> Chapter -> Topic -> SubTopic -> Pages tree per batch, plus
/// the full canvas content of every page.
///
/// Disk layout under `path_provider`'s application-support directory:
/// ```
/// mathpad_library/
///   <batchId>/
///     index.json               // MathPadLibraryIndex (tree + page metadata only)
///     pages/
///       <pageId>/
///         page.json             // full MathPadPageSnapshot
///         images/line_2.png ... // any fillImage bytes referenced by page.json
///         thumb.png             // cached small preview image (see saveThumbnail),
///                                // regenerated on every save -- the pages
///                                // sidebar reads ONLY this, never page.json,
///                                // so opening it doesn't pay a full-decode
///                                // cost per page.
/// ```
///
/// Windows/macOS/Linux/Android/iOS only -- see
/// mathpad_library_storage_service_web.dart for the web equivalent
/// (picked automatically by the mathpad_library_storage_service.dart
/// barrel; callers never need to check platform themselves).
class MathPadLibraryStorageService {
  Future<Directory> _rootDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/mathpad_library');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _batchDir(String batchId) async {
    final root = await _rootDir();
    final dir = Directory('${root.path}/$batchId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _pageDir(String batchId, String pageId) async {
    final batchDir = await _batchDir(batchId);
    return Directory('${batchDir.path}/pages/$pageId');
  }

  /// Loads this batch's library index if it already exists on disk;
  /// otherwise builds and persists a fresh one with a single default book
  /// (named [batchCourseName]) seeded 1:1 from [courseSyllabus] (the raw
  /// `course['syllabus']` list: `[{title, topics: [{title, subTopics:
  /// [{title}]}]}]`). Seeding happens exactly once -- the presence of
  /// `index.json` is the cache flag; the default book is never re-synced
  /// against the course afterwards, matching the "local only" design.
  Future<MathPadLibraryIndex> loadOrSeedIndex(
    String batchId, {
    required String batchCourseName,
    String? courseId,
    List<dynamic>? courseSyllabus,
  }) async {
    final batchDir = await _batchDir(batchId);
    final indexFile = File('${batchDir.path}/index.json');
    if (await indexFile.exists()) {
      final json = jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
      return MathPadLibraryIndex.fromJson(json);
    }

    final defaultBook = MathPadBook.create(
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

    final index = MathPadLibraryIndex(batchId: batchId, books: [defaultBook]);
    await saveIndex(batchId, index);
    return index;
  }

  /// Atomic write: serialize to a temp file, then rename over the real
  /// one, so a crash mid-write never leaves a half-written `index.json`.
  Future<void> saveIndex(String batchId, MathPadLibraryIndex index) async {
    final batchDir = await _batchDir(batchId);
    final tmpFile = File('${batchDir.path}/index.json.tmp');
    await tmpFile.writeAsString(jsonEncode(index.toJson()));
    await tmpFile.rename('${batchDir.path}/index.json');
  }

  Future<MathPadPageSnapshot> loadPage(String batchId, String pageId) async {
    final pageDir = await _pageDir(batchId, pageId);
    final pageFile = File('${pageDir.path}/page.json');
    if (!await pageFile.exists()) {
      return MathPadPageSnapshot.empty();
    }
    final json = jsonDecode(await pageFile.readAsString()) as Map<String, dynamic>;
    return decodePageSnapshot(
      json,
      readImageBytes: (relativePath) async {
        final file = File('${pageDir.path}/$relativePath');
        if (!await file.exists()) return null;
        return file.readAsBytes();
      },
    );
  }

  /// Full-overwrite-per-save: simplest correct approach for plain-JSON
  /// storage, and it naturally garbage-collects any images left over from
  /// strokes that were edited/deleted since the last save.
  Future<void> savePage(String batchId, String pageId, MathPadPageSnapshot snapshot) async {
    final pageDir = await _pageDir(batchId, pageId);
    if (!await pageDir.exists()) {
      await pageDir.create(recursive: true);
    }

    final tmpImagesDir = Directory('${pageDir.path}/images_tmp');
    if (await tmpImagesDir.exists()) {
      await tmpImagesDir.delete(recursive: true);
    }
    await tmpImagesDir.create(recursive: true);

    final json = await encodePageSnapshot(
      snapshot,
      writeImageBytes: (relativePath, pngBytes) async {
        final fileName = relativePath.split('/').last;
        await File('${tmpImagesDir.path}/$fileName').writeAsBytes(pngBytes);
      },
    );

    final tmpPageFile = File('${pageDir.path}/page.json.tmp');
    await tmpPageFile.writeAsString(jsonEncode(json));

    final imagesDir = Directory('${pageDir.path}/images');
    if (await imagesDir.exists()) {
      await imagesDir.delete(recursive: true);
    }
    await tmpImagesDir.rename(imagesDir.path);
    await tmpPageFile.rename('${pageDir.path}/page.json');
  }

  /// Persists a small cached preview image for the page -- generated once
  /// per save (see `_captureThumbnail` in `mathpad.dart`, the only place
  /// that actually rasterizes the canvas), so the pages sidebar can just
  /// display a static image instead of paying a full `loadPage` decode
  /// (JSON parse + stroke reconstruction + image-codec work) and a live
  /// vector re-render for every page just to show a thumbnail. Same
  /// atomic tmp-then-rename pattern as `savePage`/`saveIndex`.
  Future<void> saveThumbnail(String batchId, String pageId, Uint8List pngBytes) async {
    final pageDir = await _pageDir(batchId, pageId);
    if (!await pageDir.exists()) {
      await pageDir.create(recursive: true);
    }
    final tmpFile = File('${pageDir.path}/thumb.png.tmp');
    await tmpFile.writeAsBytes(pngBytes);
    await tmpFile.rename('${pageDir.path}/thumb.png');
  }

  /// Returns `null` (not an exception) when no thumbnail has been
  /// generated yet -- e.g. a page that's never been saved since this
  /// feature shipped, or a page created and not yet autosaved. The pages
  /// sidebar shows a placeholder icon in that case.
  Future<Uint8List?> loadThumbnail(String batchId, String pageId) async {
    final pageDir = await _pageDir(batchId, pageId);
    final file = File('${pageDir.path}/thumb.png');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Deletes the on-disk directory for every page in [pageIds]. The caller
  /// is responsible for calling this BEFORE removing the corresponding
  /// `MathPadPageRef`s from the index and saving it, so a crash between
  /// the two never leaves an index pointing at already-deleted content.
  Future<void> deletePages(String batchId, List<String> pageIds) async {
    for (final pageId in pageIds) {
      final pageDir = await _pageDir(batchId, pageId);
      if (await pageDir.exists()) {
        await pageDir.delete(recursive: true);
      }
    }
  }

  /// Records the page the tutor is actively viewing/editing, so the next
  /// time Math Pad is opened from the sidebar it can resume here directly
  /// instead of showing the book/chapter browser. A single global pointer
  /// (not per-batch) -- a tutor works in one place at a time, and this is
  /// meant to mirror "pick up where I left off" regardless of which batch
  /// that happened to be in.
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
    final raw = prefs.getString(_lastWorkedPrefsKey);
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
