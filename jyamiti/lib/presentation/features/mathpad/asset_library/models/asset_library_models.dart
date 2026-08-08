/// What kind of media an [AssetLibraryEntry] holds -- drives which Asset
/// Library tab it's grouped under and how it gets inserted onto the canvas
/// (see `_insertPastedImageBytes`/`_insertMediaEmbed` in `mathpad.dart`).
enum AssetKind { image, model3d, video, gif }

/// One item in the global (not per-batch) Asset Library -- either bundled
/// with the app ([isPreset]) or imported by the tutor from their device via
/// `MathPadAssetLibraryStorageService.importFile`.
///
/// Presets resolve their file straight from the Flutter asset bundle via
/// [bundleAssetPath] (no disk I/O); user-imported entries are resolved from
/// the on-disk asset library folder by [id]/[fileExtension] instead -- see
/// `MathPadAssetLibraryStorageService.absoluteFilePath`. Only user-imported
/// entries are ever written to `index.json` -- presets are always
/// re-declared in code (`mathpad_asset_presets.dart`), never serialized.
class AssetLibraryEntry {
  final String id;
  final AssetKind kind;
  final String name;
  final String fileExtension;
  final DateTime addedAt;
  final bool isPreset;

  /// Only set for presets -- the Flutter asset-bundle path to load the file
  /// from directly (e.g. `'assets/mathpad_presets/models/cube.obj'`).
  final String? bundleAssetPath;

  /// Only set for presets with a real rendered preview -- currently unused
  /// (preset 3D/video tiles use a per-kind icon instead, see
  /// `asset_grid_tile.dart`), kept for a future thumbnail pipeline.
  final String? bundleThumbnailPath;

  const AssetLibraryEntry({
    required this.id,
    required this.kind,
    required this.name,
    required this.fileExtension,
    required this.addedAt,
    this.isPreset = false,
    this.bundleAssetPath,
    this.bundleThumbnailPath,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'fileExtension': fileExtension,
    'addedAt': addedAt.toIso8601String(),
  };

  factory AssetLibraryEntry.fromJson(Map<String, dynamic> json) {
    return AssetLibraryEntry(
      id: json['id'] as String,
      kind: AssetKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => AssetKind.image,
      ),
      name: json['name'] as String? ?? 'Untitled',
      fileExtension: json['fileExtension'] as String? ?? '',
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
      isPreset: false,
    );
  }
}
