import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../asset_library/models/asset_library_models.dart';
import '../asset_library/services/mathpad_asset_library_storage_service.dart';
import 'media_embed_models.dart';

/// Renders one [MediaEmbedState] -- a GIF (via Flutter's own `Image`
/// widget, which animates GIF bytes natively) or a video (via `media_kit`).
///
/// Positioned in raw WORLD-space coordinates, same as every other
/// instrument widget (`RulerWidget`, `CompassWidget`, ...) -- the shared
/// "Geometry Instruments Overlay" `Transform` in `mathpad.dart` applies
/// pan/zoom once for the whole overlay `Stack`, so this widget never needs
/// to know about either. Dragging/rotating/resizing is likewise centralized
/// (`_hitTestInstrumentHandles`/`_updateInstrumentDrag` in `mathpad.dart`
/// against `state.handleWorldPositions()`) -- the only local
/// `GestureDetector` here is the close button; the rotate/resize handle
/// icons are purely visual (`IgnorePointer`ed), same pattern as
/// `_buildTextLabelWidget`'s resize handle.
///
/// [entry] is the already-resolved [AssetLibraryEntry] for
/// `state.assetId` (looked up by `_MathsPadWidgetState`'s in-memory asset
/// cache -- see `_assetLookupCache`) -- null if the referenced asset no
/// longer exists (e.g. deleted from the library while still embedded on
/// this page), in which case a "missing asset" placeholder renders instead
/// of crashing.
class MediaEmbedWidget extends StatefulWidget {
  final MediaEmbedState state;
  final bool isDark;
  final bool isSelected;
  final AssetLibraryEntry? entry;
  final MathPadAssetLibraryStorageService storage;
  final VoidCallback onRemove;

  /// Fired once, the first time the real decoded video's dimensions become
  /// known (media_kit only reports these asynchronously, after the file
  /// has actually started decoding) -- lets `_insertMediaEmbed`'s initial
  /// fixed 320x180 placeholder box snap to the video's true aspect ratio
  /// instead of staying wrong until the user manually resizes it. Never
  /// fired for a GIF embed (its size is already known synchronously at
  /// insert time from the decoded frame).
  final void Function(double naturalWidth, double naturalHeight)? onNaturalSizeResolved;

  const MediaEmbedWidget({
    super.key,
    required this.state,
    required this.isDark,
    required this.isSelected,
    required this.entry,
    required this.storage,
    required this.onRemove,
    this.onNaturalSizeResolved,
  });

  @override
  State<MediaEmbedWidget> createState() => _MediaEmbedWidgetState();
}

class _MediaEmbedWidgetState extends State<MediaEmbedWidget> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<VideoParams>? _videoParamsSub;
  bool _naturalSizeReported = false;
  // Cached rather than kicked off inline inside `build()`'s `FutureBuilder`
  // -- `_updateInstrumentDrag` calls `setState` on every drag/resize frame
  // in `mathpad.dart`, and a fresh `readFileBytes` call each of those
  // rebuilds would re-hit disk and show the loading spinner instead of the
  // GIF on every single frame of a drag.
  Future<Uint8List>? _gifBytesFuture;

  @override
  void initState() {
    super.initState();
    _initPlayerIfNeeded();
    _initGifBytesIfNeeded();
  }

  @override
  void didUpdateWidget(covariant MediaEmbedWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry?.id != widget.entry?.id) {
      if (!widget.state.isGif) {
        _disposePlayer();
        _initPlayerIfNeeded();
      } else {
        _initGifBytesIfNeeded();
      }
    }
  }

  void _initGifBytesIfNeeded() {
    final entry = widget.entry;
    _gifBytesFuture = (widget.state.isGif && entry != null) ? widget.storage.readFileBytes(entry) : null;
  }

  void _initPlayerIfNeeded() {
    final entry = widget.entry;
    if (widget.state.isGif || entry == null) return;
    final player = Player();
    final controller = VideoController(player);
    widget.storage.absoluteFilePath(entry).then((path) {
      if (!mounted) {
        player.dispose();
        return;
      }
      player.open(Media(path));
    });
    if (widget.onNaturalSizeResolved != null) {
      _naturalSizeReported = false;
      _videoParamsSub = player.stream.videoParams.listen((params) {
        if (_naturalSizeReported) return;
        // `dw`/`dh` are aspect-corrected (what actually gets displayed);
        // fall back to the raw `w`/`h` if those aren't reported.
        final double? w = (params.dw ?? params.w)?.toDouble();
        final double? h = (params.dh ?? params.h)?.toDouble();
        if (w == null || h == null || w <= 0 || h <= 0) return;
        _naturalSizeReported = true;
        widget.onNaturalSizeResolved!(w, h);
      });
    }
    _player = player;
    _controller = controller;
  }

  void _disposePlayer() {
    _videoParamsSub?.cancel();
    _videoParamsSub = null;
    _player?.dispose();
    _player = null;
    _controller = null;
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Positioned(
      left: state.pivot.dx - state.worldWidth / 2,
      top: state.pivot.dy - state.worldHeight / 2,
      width: state.worldWidth,
      height: state.worldHeight,
      child: Transform.rotate(
        angle: state.rotation,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: widget.isDark ? Colors.black : Colors.black12,
                  child: _buildMediaContent(),
                ),
              ),
            ),
            if (widget.isSelected) ...[
              Positioned(
                right: -9,
                top: -9,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onRemove,
                  child: _handleBadge(
                    color: const Color(0xFFEF4444),
                    icon: Icons.close_rounded,
                  ),
                ),
              ),
              // Purely visual -- the actual drag is driven by world-space
              // hit-testing in `_updateInstrumentDrag` against
              // `MediaEmbedState.handleWorldPositions()`, same as every
              // other instrument handle, so these don't carry their own
              // GestureDetector.
              Positioned(
                right: -9,
                bottom: -9,
                child: IgnorePointer(
                  child: _handleBadge(
                    color: const Color(0xFF6366F1),
                    icon: Icons.zoom_out_map_rounded,
                  ),
                ),
              ),
              Positioned(
                top: -33,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: _handleBadge(
                      color: const Color(0xFF6366F1),
                      icon: Icons.rotate_right_rounded,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _handleBadge({required Color color, required IconData icon}) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: Icon(icon, size: 12, color: Colors.white),
    );
  }

  Widget _buildMediaContent() {
    final entry = widget.entry;
    if (entry == null) return _missingAssetPlaceholder();
    if (widget.state.isGif) {
      return FutureBuilder<Uint8List>(
        future: _gifBytesFuture,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
          }
          return Image.memory(
            snap.data!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _missingAssetPlaceholder(),
          );
        },
      );
    }
    if (_controller == null) return _missingAssetPlaceholder();
    return Video(controller: _controller!);
  }

  Widget _missingAssetPlaceholder() {
    return const Center(
      child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 28),
    );
  }
}
