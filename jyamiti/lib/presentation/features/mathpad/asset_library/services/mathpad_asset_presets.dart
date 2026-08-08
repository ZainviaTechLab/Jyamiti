import '../models/asset_library_models.dart';

/// Bundled preset 3D solids for the Asset Library's 3D tab -- shipped as
/// procedurally-generated `.obj` text under `assets/mathpad_presets/models/`
/// (see the one-off generator script used to author them) rather than
/// sourced from an external asset pack, so there's no licensing question.
/// Read-only: never written to `index.json`, never deletable from the UI.
///
/// The Images and Video/GIF tabs have no presets -- only user-imported
/// entries ever appear there.
final List<AssetLibraryEntry> kPreset3DModels = [
  _preset('cube', 'Cube'),
  _preset('sphere', 'Sphere'),
  _preset('cone', 'Cone'),
  _preset('cylinder', 'Cylinder'),
  _preset('square_pyramid', 'Square Pyramid'),
  _preset('triangular_prism', 'Triangular Prism'),
];

AssetLibraryEntry _preset(String fileBaseName, String displayName) {
  return AssetLibraryEntry(
    id: 'preset_$fileBaseName',
    kind: AssetKind.model3d,
    name: displayName,
    fileExtension: 'obj',
    addedAt: DateTime(2026, 1, 1),
    isPreset: true,
    bundleAssetPath: 'assets/mathpad_presets/models/$fileBaseName.obj',
  );
}

/// Presets (where they exist for [kind]) followed by [userEntries] already
/// filtered to [kind] -- what each Asset Library tab's grid actually shows.
List<AssetLibraryEntry> mergedEntriesFor(AssetKind kind, List<AssetLibraryEntry> userEntries) {
  final filteredUser = userEntries.where((e) => e.kind == kind).toList();
  if (kind == AssetKind.model3d) {
    return [...kPreset3DModels, ...filteredUser];
  }
  return filteredUser;
}
