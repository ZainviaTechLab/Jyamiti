import 'package:flutter/material.dart';
// `flutter_cube` exports its own `Material` (mesh material, unrelated to
// Flutter's `Material` widget) -- hide it since only the mesh-loading side
// of this package is used here.
import 'package:flutter_cube/flutter_cube.dart' hide Material;

import '../models/asset_library_models.dart';
import '../services/mathpad_asset_library_storage_service.dart';

/// Full-screen orbit viewer for one 3D asset -- opened by tapping a tile on
/// the Asset Library's 3D tab (a standalone route, NOT embedded on the
/// Math Pad canvas, per the feature's requirements). Orbit (single-finger
/// drag) and zoom (pinch/scroll) are entirely handled by `flutter_cube`'s
/// own `Cube` widget (`interactive: true`, the default) -- no custom
/// gesture handling needed here.
class Model3DViewerScreen extends StatefulWidget {
  final AssetLibraryEntry entry;

  const Model3DViewerScreen({super.key, required this.entry});

  @override
  State<Model3DViewerScreen> createState() => _Model3DViewerScreenState();
}

class _Model3DViewerScreenState extends State<Model3DViewerScreen> {
  final _storage = MathPadAssetLibraryStorageService();
  bool _loading = true;
  String? _error;

  Future<void> _loadModel(Scene scene) async {
    // Default zoom (1.0) leaves a unit-radius solid at camera distance 10
    // occupying a sliver of the viewport -- bumped up so it actually fills
    // the screen. Default light sits right next to the camera (a flat
    // "headlamp" position), which combined with the default untextured
    // material's Ns=0 (a `pow(x, 0)` specular term that's ~maxed out
    // across the whole lit surface) is what made shapes look washed-out
    // with no visible edges/shading -- repositioned off-axis for real
    // depth cues, paired with each preset's own `.mtl` (distinct color,
    // Ns=20) so the specular highlight is a small spot, not a blanket.
    scene.camera.zoom = 9.0;
    // `Light` itself isn't exported by flutter_cube's public barrel, so
    // reposition/retune the `Scene`'s existing instance in place rather
    // than constructing a new one.
    scene.light.position.setValues(5, 7, 10);
    scene.light.setColor(null, 0.35, 0.75, 0.4);
    try {
      final entry = widget.entry;
      final String path = entry.isPreset ? entry.bundleAssetPath! : await _storage.absoluteFilePath(entry);

      // Load via `loadObj` directly (rather than `Object(fileName: ...)`,
      // which kicks the parse off as an internal fire-and-forget `.then()`
      // with nowhere for a caller to catch a failure) so a malformed/
      // missing file surfaces as a real error state instead of silently
      // rendering an empty scene.
      final meshes = await loadObj(path, true, isAsset: entry.isPreset);
      if (meshes.isEmpty) {
        throw StateError('No mesh data in ${entry.name}');
      }
      if (meshes.length == 1) {
        scene.world.add(Object(mesh: meshes.first, lighting: true));
      } else {
        for (final mesh in meshes) {
          scene.world.add(Object(mesh: mesh, lighting: true));
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load ${widget.entry.name}.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // `Cube`'s painter only draws the mesh's own triangles -- it never
      // fills a background itself, so this is what actually shows behind
      // the model. White gives much better contrast for judging a solid's
      // silhouette/edges than black did.
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            if (_error == null)
              Cube(onSceneCreated: (scene) => _loadModel(scene))
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.black87)),
                  ],
                ),
              ),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))),
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.white,
                elevation: 2,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF1E293B)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  widget.entry.name,
                  style: const TextStyle(color: Color(0xFF1E293B), fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
