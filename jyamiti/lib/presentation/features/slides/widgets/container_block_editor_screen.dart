import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../../providers/theme_provider.dart';
import 'columns_block_editor_screen.dart';
import 'slide_block_defaults.dart';
import 'slide_block_editor_dialog.dart';
import 'slide_block_renderer.dart';

/// Full-screen editor for a `container` block's nested content -- a
/// single flat list of blocks (any mix of types, including a nested
/// `columns` or another `container`), wrapped in one decorated box.
/// This is the counterpart to ColumnsBlockEditorScreen: same idea
/// (a dedicated screen rather than the normal block-edit dialog, since
/// "edit a whole list of nested blocks" doesn't fit that dialog's
/// content/style shape), just a single area instead of side-by-side
/// columns -- and, unlike columns, the container's OWN box styling
/// (background/outline/radius/padding/margin) is edited right here too
/// via ContainerStyleSection, since a container with no way to
/// customize its own box would defeat the point of it.
class ContainerBlockEditorScreen extends StatefulWidget {
  final SlideBlock block;

  const ContainerBlockEditorScreen({super.key, required this.block});

  @override
  State<ContainerBlockEditorScreen> createState() =>
      _ContainerBlockEditorScreenState();
}

class _ContainerBlockEditorScreenState
    extends State<ContainerBlockEditorScreen> {
  late List<SlideBlock> _children;
  String? _bg;
  String? _border;
  double _borderWidth = 0;
  double _borderRadius = 14;
  double _padding = 14;
  double _margin = 6;
  double _width = 100;
  double _minHeight = 0;
  String _horizontalAlign = 'left';
  String _verticalAlign = 'top';
  String _selfAlign = 'center';

  @override
  void initState() {
    super.initState();
    _children = _parseChildren(widget.block.content);
    _bg = widget.block.backgroundColor;
    _border = widget.block.borderColor;
    _borderWidth = widget.block.borderWidth;
    _borderRadius = widget.block.borderRadius ?? 14;
    _padding = widget.block.padding ?? 14;
    _margin = widget.block.marginVertical ?? 6;
    _width = (widget.block.width ?? 1.0) * 100;
    _minHeight = widget.block.minHeight ?? 0;
    _horizontalAlign = widget.block.horizontalAlign ?? 'left';
    _verticalAlign = widget.block.verticalAlign ?? 'top';
    _selfAlign = widget.block.selfAlign ?? 'center';
  }

  List<SlideBlock> _parseChildren(String content) {
    try {
      final data = json.decode(content) as Map<String, dynamic>;
      final raw = data['children'] as List? ?? [];
      return raw
          .map((b) => SlideBlock.fromMap(b as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    return <SlideBlock>[];
  }

  void _save() {
    final content =
        jsonEncode({'children': _children.map((b) => b.toMap()).toList()});
    Navigator.pop(
      context,
      widget.block.copyWith(
        content: content,
        backgroundColor: _bg,
        clearBackgroundColor: _bg == null,
        borderColor: _border,
        clearBorderColor: _border == null,
        borderWidth: _borderWidth,
        borderRadius: _borderRadius,
        padding: _padding,
        marginVertical: _margin,
        width: _width >= 100 ? null : _width / 100,
        clearWidth: _width >= 100,
        minHeight: _minHeight <= 0 ? null : _minHeight,
        clearMinHeight: _minHeight <= 0,
        horizontalAlign: _horizontalAlign,
        verticalAlign: _verticalAlign,
        selfAlign: _selfAlign,
      ),
    );
  }

  void _addBlock(SlideBlockType type) {
    final defaults = defaultBlockContentFor(type);
    setState(() {
      _children.add(
        applyBannerDefaults(
          SlideBlock(
            id: 'cc_${DateTime.now().millisecondsSinceEpoch}',
            type: type,
            content: defaults.content,
            extra: defaults.extra,
          ),
        ),
      );
    });
  }

  /// Routes columns/container children to their own dedicated editor
  /// screens (recursively -- a container can hold a columns block or
  /// another container), everything else through the shared dialog --
  /// same routing AdminSlideCmsScreen._editBlock and
  /// StudentSlideViewerScreen._editBlockAt use at the top level.
  Future<void> _editChild(int idx) async {
    final block = _children[idx];

    final SlideBlock? updated;
    if (block.type == SlideBlockType.columns) {
      updated = await Navigator.push<SlideBlock>(
        context,
        MaterialPageRoute(
          builder: (_) => ColumnsBlockEditorScreen(block: block),
        ),
      );
    } else if (block.type == SlideBlockType.container) {
      updated = await Navigator.push<SlideBlock>(
        context,
        MaterialPageRoute(
          builder: (_) => ContainerBlockEditorScreen(block: block),
        ),
      );
    } else {
      if (!mounted) return;
      updated = await showSlideBlockEditorDialog(context, block);
    }
    if (updated == null || !mounted) return;
    setState(() => _children[idx] = updated!);
  }

  void _deleteChild(int idx) {
    setState(() => _children.removeAt(idx));
  }

  /// Changes what kind of block this is (e.g. paragraph -> text, text ->
  /// card) via the type label's own tap target -- see
  /// pickSlideBlockType's doc comment for why content/extra/caption/
  /// style fields are all left exactly as they were.
  Future<void> _changeChildType(int idx) async {
    final block = _children[idx];
    final newType = await pickSlideBlockType(context, block.type);
    if (newType == null || !mounted) return;
    setState(() => _children[idx] = block.copyWith(type: newType));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _children.removeAt(oldIndex);
      _children.insert(newIndex, moved);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Edit Container (${_children.length} block${_children.length == 1 ? '' : 's'})',
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Done'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ContainerStyleSection(
              backgroundColor: _bg,
              onBackgroundColorChanged: (val) => setState(() => _bg = val),
              borderColor: _border,
              onBorderColorChanged: (val) => setState(() => _border = val),
              borderWidth: _borderWidth,
              onBorderWidthChanged: (val) =>
                  setState(() => _borderWidth = val),
              borderRadius: _borderRadius,
              onBorderRadiusChanged: (val) =>
                  setState(() => _borderRadius = val),
              padding: _padding,
              onPaddingChanged: (val) => setState(() => _padding = val),
              margin: _margin,
              onMarginChanged: (val) => setState(() => _margin = val),
              width: _width,
              onWidthChanged: (val) => setState(() => _width = val),
              minHeight: _minHeight,
              onMinHeightChanged: (val) => setState(() => _minHeight = val),
              horizontalAlign: _horizontalAlign,
              onHorizontalAlignChanged: (val) =>
                  setState(() => _horizontalAlign = val),
              verticalAlign: _verticalAlign,
              onVerticalAlignChanged: (val) =>
                  setState(() => _verticalAlign = val),
              selfAlign: _selfAlign,
              onSelfAlignChanged: (val) => setState(() => _selfAlign = val),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Blocks Inside',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: SlideBlockType.values.map((type) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ActionChip(
                      avatar: Icon(iconForSlideBlockType(type), size: 14),
                      label: Text(
                        displayNameForSlideBlockType(type),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => _addBlock(type),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            if (_children.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'No blocks yet -- use the chips above to add one.',
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF64748B)
                        : const Color(0xFF94A3B8),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _children.length,
                onReorder: _reorder,
                itemBuilder: (context, idx) {
                  final b = _children[idx];
                  return Card(
                    key: ValueKey(b.id),
                    margin: const EdgeInsets.only(bottom: 12),
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ReorderableDragStartListener(
                                index: idx,
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 8.0),
                                  child: Icon(
                                    Icons.drag_indicator_rounded,
                                    size: 18,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _changeChildType(idx),
                                child: Chip(
                                  label: Text(
                                    displayNameForSlideBlockType(b.type),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                    ),
                                  ),
                                  avatar: const Icon(
                                    Icons.swap_horiz_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                  backgroundColor: const Color(0xFF6366F1),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon:
                                    const Icon(Icons.edit_rounded, size: 16),
                                onPressed: () => _editChild(idx),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_rounded,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                onPressed: () => _deleteChild(idx),
                              ),
                            ],
                          ),
                          SlideBlockRenderer(block: b, isDark: isDark),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
