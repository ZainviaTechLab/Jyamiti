import 'dart:io';

import 'package:flutter/material.dart';

import 'package:jyamiti/providers/theme_provider.dart';

import '../models/asset_library_models.dart';
import '../services/mathpad_asset_library_storage_service.dart';

/// One thumbnail tile in an [AssetLibraryPickerSheet] tab grid. Styled to
/// match `FullSymbolPickerModal`'s grid tiles (same rounded container/
/// border treatment) for visual consistency with the rest of Math Pad's
/// picker UI.
///
/// Thumbnail content depends on [entry.kind]: images/GIFs render the real
/// file (Flutter's `Image` widget animates GIF bytes natively, even at
/// this small grid size); 3D models and videos render a fixed per-kind
/// icon -- neither a rendered-model preview nor a video-frame thumbnail is
/// generated, a deliberate v1 simplification (see the Asset Library plan).
class AssetGridTile extends StatelessWidget {
  final AssetLibraryEntry entry;
  final MathPadAssetLibraryStorageService storage;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const AssetGridTile({
    super.key,
    required this.entry,
    required this.storage,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: _buildThumbnail(isDark),
          ),
          if (onDelete != null)
            Positioned(
              right: -6,
              top: -6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDelete,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(bool isDark) {
    switch (entry.kind) {
      case AssetKind.image:
      case AssetKind.gif:
        if (entry.isPreset && entry.bundleAssetPath != null) {
          return Image.asset(entry.bundleAssetPath!, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
        }
        return FutureBuilder<String>(
          future: storage.absoluteFilePath(entry),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
            }
            return Image.file(
              File(snap.data!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _kindIcon(isDark),
            );
          },
        );
      case AssetKind.model3d:
        return _kindIcon(isDark);
      case AssetKind.video:
        return _kindIcon(isDark);
    }
  }

  Widget _kindIcon(bool isDark) {
    final IconData icon = switch (entry.kind) {
      AssetKind.model3d => Icons.view_in_ar_rounded,
      AssetKind.video => Icons.movie_rounded,
      AssetKind.gif => Icons.gif_rounded,
      AssetKind.image => Icons.image_rounded,
    };
    return Icon(icon, size: 28, color: isDark ? Colors.white54 : Colors.black45);
  }
}
