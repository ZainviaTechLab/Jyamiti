# Vendored fork of `flutter_cube` 0.1.1

Vendored (not pulled from pub.dev) specifically to patch its lighting model,
which computes a single flat face-normal per triangle at render time and
never reads/computes true vertex normals -- meaning every curved solid
(sphere/cylinder/cone) rendered with hard, visible polygon facets no matter
how high the segment count, since flutter_cube has no way to blend shading
smoothly across adjacent faces.

## What's patched

- `lib/src/mesh.dart` -- `Mesh` now computes `cornerNormals` (one averaged
  normal per (face, corner) instance) at construction time via
  `_computeCornerNormals`: for each triangle corner, average the face
  normals of every OTHER face sharing that vertex whose face-normal is
  within `_smoothAngleThresholdDeg` (40°) of this face's own normal.
  Faces meeting at a sharper angle than that (a cube's 90° edges, a
  cylinder's flat-cap-to-round-side seam) are deliberately excluded from
  each other's average, so genuinely flat/hard-edged geometry stays crisp
  while curved surfaces blend smoothly -- the same "shade smooth with an
  auto-smooth angle" technique modeling tools like Blender use.
- `lib/src/scene.dart` -- `_renderObject`'s lighting branch now looks up
  `o.mesh.cornerNormals[faceIndex * 3 + corner]` instead of recomputing a
  flat `normalVector(a, b, c)` per triangle every frame.
- `lib/src/mesh.dart` (`loadObj`) + `lib/src/material.dart` (`loadTexture`)
  -- `package:path`'s default top-level `join`/`dirname` use platform-style
  separators (backslash on Windows), but a Flutter asset-bundle key is
  always forward-slash. On Windows, resolving a `mtllib`/texture reference
  for an `isAsset: true` (bundled) `.obj` produced a path matching no real
  asset -- `rootBundle.loadString` threw, and the caller silently swallows
  that into an empty material map, so every asset-bundled model with a
  `.mtl` silently fell back to the default (gray, dim) material with no
  error surfaced anywhere. Both now force posix-style joining specifically
  when `isAsset` is true; `isAsset: false` (a real filesystem path, e.g. a
  user-imported model) is untouched and still uses the platform's own
  separator, which is what `dart:io`'s `File()` actually needs there.

Everything else is untouched from the original 0.1.1 release
(https://github.com/zesage/flutter_cube).
