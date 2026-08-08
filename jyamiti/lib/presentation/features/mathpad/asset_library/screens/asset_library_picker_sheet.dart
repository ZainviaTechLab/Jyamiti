import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:jyamiti/providers/theme_provider.dart';

import '../../screens/mathpad.dart' show MathsPadLine;
import '../models/asset_library_models.dart';
import '../models/mathpad_template_models.dart';
import '../services/mathpad_asset_library_storage_service.dart';
import '../services/mathpad_asset_presets.dart';
import '../widgets/asset_grid_tile.dart';
import 'model_3d_viewer_screen.dart';

/// The Asset Library's 4-tab bottom sheet -- Images / 3D / Video-GIFs /
/// Templates. Structurally mirrors `FullSymbolPickerModal`
/// (`symbol_picker_toolbar.dart`) -- same drag handle/title/close row,
/// `TabBar`+`TabBarView`, and `GridView.builder` sizing -- for visual
/// consistency with the rest of Math Pad's picker UI.
///
/// Tapping an Images or Video/GIF tile closes the sheet and hands the
/// selected [AssetLibraryEntry] back to the caller (`_MathsPadWidgetState`
/// in `mathpad.dart`, which owns the actual canvas-insertion logic -- this
/// widget deliberately knows nothing about `MathsPadLine`/`_instruments`).
/// A 3D tile instead closes the sheet and pushes [Model3DViewerScreen]
/// directly (a standalone viewer, not embedded on canvas, so no callback
/// is needed for it). A Templates tile hands back a [MathPadTemplate].
class AssetLibraryPickerSheet extends StatefulWidget {
  final void Function(AssetLibraryEntry imageEntry) onImageSelected;
  final void Function(AssetLibraryEntry mediaEntry) onVideoOrGifSelected;
  final void Function(MathPadTemplate template) onTemplateSelected;

  const AssetLibraryPickerSheet({
    super.key,
    required this.onImageSelected,
    required this.onVideoOrGifSelected,
    required this.onTemplateSelected,
  });

  @override
  State<AssetLibraryPickerSheet> createState() => _AssetLibraryPickerSheetState();
}

class _AssetLibraryPickerSheetState extends State<AssetLibraryPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _storage = MathPadAssetLibraryStorageService();
  late Future<List<AssetLibraryEntry>> _userEntriesFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _refreshEntries();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshEntries() {
    _userEntriesFuture = kIsWeb ? Future.value(const []) : _storage.loadIndex();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleAdd({
    required List<String> allowedExtensions,
    required AssetKind Function(String ext) resolveKind,
  }) async {
    if (kIsWeb) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    final String ext = (file.extension ?? (file.name.contains('.') ? file.name.split('.').last : ''))
        .toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      _showSnack('Only ${allowedExtensions.map((e) => '.$e').join(', ')} files are supported here.');
      return;
    }
    final String name = file.name.contains('.') ? file.name.substring(0, file.name.lastIndexOf('.')) : file.name;

    await _storage.importFile(kind: resolveKind(ext), suggestedName: name, bytes: bytes, fileExtension: ext);
    setState(_refreshEntries);
  }

  /// Same shape as [_handleAdd], but specific to the 3D tab: after the
  /// `.obj` is picked, optionally offers a second pick for a matching
  /// `.mtl` material file (skippable -- most `.obj` exports still render
  /// fine, just without color, without one). Kept as a separate method
  /// rather than folding a conditional second-pick into `_handleAdd`
  /// itself since no other tab needs a multi-file import flow.
  Future<void> _handleAdd3DModel() async {
    if (kIsWeb) return;
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['obj'], withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    final String ext = (file.extension ?? (file.name.contains('.') ? file.name.split('.').last : '')).toLowerCase();
    if (ext != 'obj') {
      _showSnack('Only .obj files are supported for 3D models.');
      return;
    }
    final String name = file.name.contains('.') ? file.name.substring(0, file.name.lastIndexOf('.')) : file.name;

    if (!mounted) return;
    final bool addMaterial = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Add a material file?'),
            content: const Text(
              'If this .obj came with a matching .mtl file, add it now for colors/shading. '
              'You can skip this -- the model will still render, just untextured.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Skip')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add .mtl')),
            ],
          ),
        ) ??
        false;

    Uint8List? mtlBytes;
    if (addMaterial) {
      final mtlResult = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['mtl'], withData: true);
      mtlBytes = (mtlResult != null && mtlResult.files.isNotEmpty) ? mtlResult.files.first.bytes : null;
      if (mtlBytes == null) {
        _showSnack('No .mtl selected -- importing the model without one.');
      }
    }

    await _storage.importFile(
      kind: AssetKind.model3d,
      suggestedName: name,
      bytes: bytes,
      fileExtension: 'obj',
      mtlBytes: mtlBytes,
    );
    setState(_refreshEntries);
  }

  Future<void> _handleDelete(AssetLibraryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete from library?'),
        content: Text('"${entry.name}" will be removed from your Asset Library. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.deleteEntry(entry.id);
    setState(_refreshEntries);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                const Icon(Icons.perm_media_rounded, color: Color(0xFF6366F1), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Asset Library',
                  style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: const Color(0xFF6366F1),
            unselectedLabelColor: context.textColor60,
            indicatorColor: const Color(0xFF6366F1),
            tabs: const [
              Tab(icon: Icon(Icons.image_rounded, size: 18), text: 'Images'),
              Tab(icon: Icon(Icons.view_in_ar_rounded, size: 18), text: '3D'),
              Tab(icon: Icon(Icons.movie_rounded, size: 18), text: 'Video/GIFs'),
              Tab(icon: Icon(Icons.dashboard_customize_rounded, size: 18), text: 'Templates'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAssetTab(
                  kind: AssetKind.image,
                  onAdd: () => _handleAdd(
                    allowedExtensions: const ['png', 'jpg', 'jpeg'],
                    resolveKind: (_) => AssetKind.image,
                  ),
                  emptyMessage: 'No images yet -- tap Add to import one.',
                  onTap: (entry) {
                    Navigator.pop(context);
                    widget.onImageSelected(entry);
                  },
                ),
                _buildAssetTab(
                  kind: AssetKind.model3d,
                  onAdd: _handleAdd3DModel,
                  emptyMessage: 'No 3D models yet -- tap Add to import a .obj file.',
                  onTap: (entry) {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => Model3DViewerScreen(entry: entry)),
                    );
                  },
                ),
                _buildVideoGifTab(),
                _buildTemplatesTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetTab({
    required AssetKind kind,
    required Future<void> Function() onAdd,
    required String emptyMessage,
    required void Function(AssetLibraryEntry) onTap,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: kIsWeb ? null : onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(kIsWeb ? 'Add (unavailable on web)' : 'Add'),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AssetLibraryEntry>>(
            future: _userEntriesFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final merged = mergedEntriesFor(kind, snap.data ?? const []);
              if (merged.isEmpty) return _emptyState(emptyMessage);
              return _grid(merged, onTap);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVideoGifTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: kIsWeb
                  ? null
                  : () => _handleAdd(
                      allowedExtensions: const ['mp4', 'mov', 'webm', 'gif'],
                      resolveKind: (ext) => ext == 'gif' ? AssetKind.gif : AssetKind.video,
                    ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(kIsWeb ? 'Add (unavailable on web)' : 'Add'),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AssetLibraryEntry>>(
            future: _userEntriesFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final merged = (snap.data ?? const [])
                  .where((e) => e.kind == AssetKind.video || e.kind == AssetKind.gif)
                  .toList();
              if (merged.isEmpty) return _emptyState('No video/GIF clips yet -- tap Add to import one.');
              return _grid(merged, (entry) {
                Navigator.pop(context);
                widget.onVideoOrGifSelected(entry);
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _grid(List<AssetLibraryEntry> entries, void Function(AssetLibraryEntry) onTap) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 75,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.2,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return AssetGridTile(
          entry: entry,
          storage: _storage,
          onTap: () => onTap(entry),
          onDelete: entry.isPreset ? null : () => _handleDelete(entry),
        );
      },
    );
  }

  Widget _buildTemplatesTab(bool isDark) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 75,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.2,
      ),
      itemCount: kPresetTemplates.length,
      itemBuilder: (context, i) {
        final template = kPresetTemplates[i];
        return InkWell(
          onTap: () {
            Navigator.pop(context);
            widget.onTemplateSelected(template);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
            child: CustomPaint(painter: _TemplateThumbnailPainter(template.buildLines(), isDark)),
          ),
        );
      },
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.textColor60, fontSize: 13),
        ),
      ),
    );
  }
}

/// Cheap, always-accurate template preview: draws the template's actual
/// [MathsPadLine]s scaled/centered to fit the tile, instead of a separately
/// authored/maintained thumbnail image.
class _TemplateThumbnailPainter extends CustomPainter {
  final List<MathsPadLine> lines;
  final bool isDark;
  _TemplateThumbnailPainter(this.lines, this.isDark);

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty) return;
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final line in lines) {
      for (final p in line.points) {
        if (p.offset.dx < minX) minX = p.offset.dx;
        if (p.offset.dy < minY) minY = p.offset.dy;
        if (p.offset.dx > maxX) maxX = p.offset.dx;
        if (p.offset.dy > maxY) maxY = p.offset.dy;
      }
    }
    final double w = (maxX - minX).clamp(1.0, double.infinity);
    final double h = (maxY - minY).clamp(1.0, double.infinity);
    const double padding = 8.0;
    final double scale = ((size.width - padding * 2) / w).clamp(0.0, (size.height - padding * 2) / h);
    final double centerX = (minX + maxX) / 2;
    final double centerY = (minY + maxY) / 2;

    Offset map(Offset p) => Offset(
      (p.dx - centerX) * scale + size.width / 2,
      (p.dy - centerY) * scale + size.height / 2,
    );

    for (final line in lines) {
      if (line.points.isEmpty) continue;
      final path = Path()..moveTo(map(line.points.first.offset).dx, map(line.points.first.offset).dy);
      for (final p in line.points.skip(1)) {
        final mapped = map(p.offset);
        path.lineTo(mapped.dx, mapped.dy);
      }
      final paint = Paint()
        ..color = line.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TemplateThumbnailPainter oldDelegate) => false;
}
