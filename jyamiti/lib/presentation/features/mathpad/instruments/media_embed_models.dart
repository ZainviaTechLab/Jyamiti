import 'package:flutter/material.dart' show Offset;

import 'instrument_models.dart';

/// A video or GIF from the Asset Library, embedded onto the canvas as a
/// draggable/rotatable/resizable overlay (not baked into a static
/// `MathsPadLine` the way a pasted image is -- see `_insertPastedImageBytes`
/// vs `_insertMediaEmbed` in `mathpad.dart`).
///
/// Stores only a reference ([assetId]) into the global Asset Library, never
/// the media bytes themselves -- resolved lazily at render time by
/// `_MathsPadWidgetState`'s asset lookup cache, so editing/replacing the
/// underlying asset is reflected everywhere it's embedded, and multiple
/// embeds of the same asset don't duplicate bytes on disk or in `page.json`.
///
/// Unlike the geometry instruments this sits alongside in `_instruments`,
/// there's deliberately no `'remove'` handle key here -- Ruler/Protractor/
/// SetSquare declare one but no widget actually renders/wires a tap target
/// for it (dead code); `MediaEmbedWidget` instead gets a real local close
/// button, shown only while selected, following `_buildTextLabelWidget`'s
/// pattern.
class MediaEmbedState extends InstrumentState {
  final String assetId;
  final bool isGif;

  /// Natural size (already downscaled to fit Math Pad's usual `maxDim`
  /// on-canvas cap, same as a pasted image) at [scale] == 1.0. Mutable for
  /// a video embed: inserted with a fixed 16:9 placeholder box (media_kit
  /// only reports the real decoded dimensions asynchronously), then
  /// snapped to the true aspect ratio once `MediaEmbedWidget` reports it
  /// via `onNaturalSizeResolved` -- see `_updateMediaEmbedNaturalSize` in
  /// `mathpad.dart`. Already known synchronously (never mutated) for GIFs.
  double baseWidth;
  double baseHeight;

  /// Mutable, driven by the generic `'resize'` handle in
  /// `_updateInstrumentDrag` -- same shape as `SetSquareState.scale`.
  double scale;

  MediaEmbedState({
    required super.pivot,
    super.rotation = 0,
    required this.assetId,
    required this.isGif,
    required this.baseWidth,
    required this.baseHeight,
    this.scale = 1.0,
  });

  double get worldWidth => baseWidth * scale;
  double get worldHeight => baseHeight * scale;

  @override
  Map<String, Offset> handleWorldPositions() => {
    'move': pivot,
    'rotate': rotatedLocal(0, -worldHeight / 2 - 24),
    'resize': rotatedLocal(worldWidth / 2, worldHeight / 2),
  };
}
