import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../library/models/mathpad_library_models.dart' show newMathPadLibraryId;
import '../models/asset_library_models.dart';

/// On-device (no backend sync) persistence for the **global** Math Pad
/// Asset Library -- unlike `MathPadLibraryStorageService` (the per-batch
/// page/notebook library), this is one shared pool of imported images/3D
/// models/video/GIFs available from every batch and page, since a tutor's
/// personal media (a favourite diagram, a 3D solid) is reused across
/// courses, not scoped to one.
///
/// Disk layout under `path_provider`'s application-support directory:
/// ```
/// mathpad_asset_library/
///   index.json          // List<AssetLibraryEntry> (user-imported only -- presets are never persisted here)
///   files/
///     <assetId>.<ext>    // the imported file itself
///     <assetId>.mtl       // optional companion material file for a model3d entry, see importFile()
/// ```
///
/// Not usable on web (no real filesystem) -- callers must gate on `kIsWeb`
/// before touching this service at all, same as `MathPadLibraryStorageService`.
class MathPadAssetLibraryStorageService {
  Future<Directory> _rootDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/mathpad_asset_library');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _filesDir() async {
    final root = await _rootDir();
    final dir = Directory('${root.path}/files');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<AssetLibraryEntry>> loadIndex() async {
    final root = await _rootDir();
    final indexFile = File('${root.path}/index.json');
    if (!await indexFile.exists()) return [];
    final raw = jsonDecode(await indexFile.readAsString()) as List;
    return raw.map((e) => AssetLibraryEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Atomic write: serialize to a temp file, then rename over the real
  /// one, so a crash mid-write never leaves a half-written `index.json`.
  Future<void> _saveIndex(List<AssetLibraryEntry> entries) async {
    final root = await _rootDir();
    final tmpFile = File('${root.path}/index.json.tmp');
    await tmpFile.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
    await tmpFile.rename('${root.path}/index.json');
  }

  /// Copies [bytes] into the library's `files/` folder under a freshly
  /// minted id, appends a new [AssetLibraryEntry] to the index, and
  /// returns it. Extension validation (e.g. rejecting non-`.obj` on the 3D
  /// tab) is the caller's responsibility -- this method trusts [fileExtension].
  ///
  /// [mtlBytes], only meaningful for `AssetKind.model3d`, is an optional
  /// companion Wavefront material file picked alongside the `.obj` --
  /// written as `<id>.mtl` and the `.obj` text's own `mtllib` reference (if
  /// any) is rewritten to point at that exact renamed file before either is
  /// saved, so `flutter_cube`'s loader (which resolves `mtllib` purely by
  /// filename, relative to the `.obj`'s own directory) finds it regardless
  /// of what the user's original `.mtl` was actually named -- also
  /// sidesteps two different imports both shipping a generically-named
  /// `material.mtl` colliding in the shared `files/` folder. Texture image
  /// references inside the `.mtl` (`map_Kd ...`) are NOT rewritten/copied
  /// -- out of scope for now, so an imported model with image textures will
  /// still render (using its `.mtl`'s plain Kd/Ka/Ks colors) but without
  /// those textures.
  Future<AssetLibraryEntry> importFile({
    required AssetKind kind,
    required String suggestedName,
    required Uint8List bytes,
    required String fileExtension,
    Uint8List? mtlBytes,
  }) async {
    final id = newMathPadLibraryId();
    final filesDir = await _filesDir();

    Uint8List objBytes = bytes;
    if (mtlBytes != null && kind == AssetKind.model3d) {
      final rewritten = _rewriteMtllibReference(utf8.decode(bytes, allowMalformed: true), '$id.mtl');
      objBytes = Uint8List.fromList(utf8.encode(rewritten));
      await File('${filesDir.path}/$id.mtl').writeAsBytes(mtlBytes);
    }
    await File('${filesDir.path}/$id.$fileExtension').writeAsBytes(objBytes);

    final entry = AssetLibraryEntry(
      id: id,
      kind: kind,
      name: suggestedName,
      fileExtension: fileExtension,
      addedAt: DateTime.now(),
    );
    final entries = await loadIndex();
    entries.add(entry);
    await _saveIndex(entries);
    return entry;
  }

  /// Replaces the filename on an existing `mtllib <name>` line with
  /// [newMtlFileName], or inserts `mtllib <newMtlFileName>` as the very
  /// first line if the `.obj` doesn't declare one at all (some exporters
  /// omit it even when a material was intended) -- inserting at the top is
  /// safe since every parser reads `.obj` files sequentially and only
  /// needs `mtllib` resolved before the `usemtl` lines that reference it.
  String _rewriteMtllibReference(String objText, String newMtlFileName) {
    final lines = objText.split('\n');
    bool found = false;
    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('mtllib ')) {
        lines[i] = 'mtllib $newMtlFileName';
        found = true;
        break;
      }
    }
    if (!found) {
      lines.insert(0, 'mtllib $newMtlFileName');
    }
    return lines.join('\n');
  }

  /// Removes [assetId] from the index and deletes its file(s) on disk.
  /// Only ever meaningful for user-imported entries -- presets aren't in
  /// the index and have nothing on disk to delete.
  Future<void> deleteEntry(String assetId) async {
    final entries = await loadIndex();
    final match = entries.where((e) => e.id == assetId).toList();
    entries.removeWhere((e) => e.id == assetId);
    await _saveIndex(entries);

    final filesDir = await _filesDir();
    for (final entry in match) {
      final file = File('${filesDir.path}/${entry.id}.${entry.fileExtension}');
      if (await file.exists()) {
        await file.delete();
      }
      // Companion material file, if this was a model3d import with one --
      // harmless no-op (file just won't exist) for every other entry.
      final mtlFile = File('${filesDir.path}/${entry.id}.mtl');
      if (await mtlFile.exists()) {
        await mtlFile.delete();
      }
    }
  }

  /// The real filesystem path for a **user-imported** [entry] -- what
  /// `flutter_cube`'s `Object(fileName:)` and `media_kit`'s `Media(path:)`
  /// both want. Never call this for a preset entry (it has no on-disk
  /// file -- use `entry.bundleAssetPath` with `Image.asset`/the asset
  /// bundle loader instead).
  Future<String> absoluteFilePath(AssetLibraryEntry entry) async {
    assert(!entry.isPreset, 'Presets are loaded from the asset bundle, not disk.');
    final filesDir = await _filesDir();
    return '${filesDir.path}/${entry.id}.${entry.fileExtension}';
  }

  Future<Uint8List> readFileBytes(AssetLibraryEntry entry) async {
    final path = await absoluteFilePath(entry);
    return File(path).readAsBytes();
  }
}
