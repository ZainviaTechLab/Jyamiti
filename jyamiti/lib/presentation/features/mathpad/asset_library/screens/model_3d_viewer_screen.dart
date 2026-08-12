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
    // occupying a sliver of the viewport -- 9.0 (an earlier pass) turned
    // out too aggressive for a taller solid like the cylinder (ran off the
    // edges of the frame); this leaves comfortable margin on every preset.
    scene.camera.zoom = 5.5;
    // Camera-following "headlight" (near the camera, not off to one side)
    // -- this is an orbit viewer the user freely rotates, so a fixed
    // off-axis light (an earlier pass) inevitably rotates SOME orientation
    // into near-shadow. A near-camera light stays roughly front-on no
    // matter how the model is spun, the same way most simple CAD-style
    // viewers do it. Slight offset (not exactly coincident with the
    // camera) so there's still a soft directional gradient for depth
    // cues, not a completely flat look.
    //
    // `Light.shading`'s ambient term is `material.ambient * light.ambient`.
    // An earlier pass had each preset's `.mtl` set `Ka` (material.ambient)
    // to only ~35% of its `Kd`, so even a high `light.ambient` scalar left
    // the guaranteed floor at well under half the shape's real color --
    // reading as flatly "dark". Overcorrecting to ~75% then went the other
    // way: with `light.ambient` this high, the floor alone landed so close
    // to full brightness that there was barely any headroom left for
    // diffuse to create a visible gradient -- shapes looked flat/edgeless,
    // not three-dimensional. Settled on `Ka` = 50% of `Kd` (see the
    // generator script) -- the same floor `_ensureReasonableAmbient` below
    // applies to anything that arrives dimmer than that (an unmaterialed
    // import, or a real-world `.mtl` with a low/legacy `Ka`), so presets
    // and imports both get a consistent balance of "never too dark" and
    // "still has a real shading gradient" -- paired with the smooth
    // per-vertex normals patched into the vendored flutter_cube (see
    // third_party/flutter_cube/PATCH_NOTES.md), this is what actually
    // gives a curved solid the soft, clearly-3D look requested.
    scene.light.position.setValues(-2, 3, -9.5);
    // Verified via a direct screenshot: the 0.35 diffuse scalar (an
    // earlier pass) technically produced a gradient, but too low-contrast
    // to read as clearly 3D -- ambient(0.5*Kd) to diffuse-lit(~0.9*Kd) is
    // barely a 0.15-0.2 swing on top of an already-bright floor. Raised
    // to 0.6 for real visible contrast; the floor itself is untouched, so
    // this only widens the lit-vs-shadowed swing, it doesn't risk the
    // earlier near-black problem.
    scene.light.setColor(null, 1.0, 0.6, 0.1);
    try {
      final entry = widget.entry;
      final String path = entry.isPreset
          ? entry.bundleAssetPath!
          : await _storage.absoluteFilePath(entry);

      // Load via `loadObj` directly (rather than `Object(fileName: ...)`,
      // which kicks the parse off as an internal fire-and-forget `.then()`
      // with nowhere for a caller to catch a failure) so a malformed/
      // missing file surfaces as a real error state instead of silently
      // rendering an empty scene.
      final meshes = await loadObj(path, true, isAsset: entry.isPreset);
      if (meshes.isEmpty) {
        throw StateError('No mesh data in ${entry.name}');
      }
      for (final mesh in meshes) {
        _ensureReasonableAmbient(mesh);
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

  /// A floor, not an override: many real-world `.obj`/`.mtl` exports set
  /// `Ka` (ambient) to `0` or something very low as a legacy/unused
  /// convention -- most modern viewers barely use it, treating diffuse as
  /// the real base color, but `flutter_cube`'s renderer takes `Ka`
  /// completely literally as a hard multiplicative floor
  /// (`material.ambient * light.ambient`, added to diffuse/specular). A
  /// perfectly normal `.mtl` with a low `Ka` -- or no `.mtl` at all, which
  /// leaves `flutter_cube`'s built-in default `Material()` with `Ka` at
  /// just 12.5% of `Kd` -- both end up rendering noticeably darker here
  /// than in another viewer showing the same file. Clamped up to at least
  /// 50% of `Kd` per channel -- the same ratio the presets' own `.mtl`s
  /// now set directly, so this is a no-op safety net for them and the
  /// actual fix for anything dimmer. A `.mtl` that already sets a
  /// brighter `Ka` than that is left exactly as authored.
  void _ensureReasonableAmbient(Mesh mesh) {
    final Vector3 ka = mesh.material.ambient;
    final Vector3 kd = mesh.material.diffuse;
    mesh.material.ambient = Vector3(
      ka.x > kd.x * 0.5 ? ka.x : kd.x * 0.5,
      ka.y > kd.y * 0.5 ? ka.y : kd.y * 0.5,
      ka.z > kd.z * 0.5 ? ka.z : kd.z * 0.5,
    );
  }

  void _updateLight(Scene scene) {
    // Keep light locked to the camera's current perspective so it never leaves
    // the model in shadow as the user spins it.
    final camera = scene.camera;
    final eye = camera.position - camera.target;
    final eyeDirection = eye.normalized();
    final upDirection = camera.up.normalized();
    final sidewaysDirection = upDirection.cross(eyeDirection).normalized();

    // Offset relative to camera: left 2, up 3, forward 0.5 (toward target).
    // `setFrom` returns void (not chainable), so it can't lead a cascade --
    // reset the position first, then cascade the offsets onto it directly.
    final Vector3 lightPos = scene.light.position;
    lightPos.setFrom(camera.position);
    lightPos
      ..addScaled(sidewaysDirection, 2.0) // Left 2 units (sidewaysDirection is -X initially)
      ..addScaled(upDirection, 3.0) // Up 3 units
      ..addScaled(eyeDirection, -0.5); // 0.5 units in front (eyeDirection is -Z initially)
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
              Cube(
                onSceneCreated: (scene) => _loadModel(scene),
                onSceneUpdate: (scene) => _updateLight(scene),
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ],
                ),
              ),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF6366F1)),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.white,
                elevation: 2,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF1E293B),
                  ),
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
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
