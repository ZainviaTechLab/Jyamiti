import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../../providers/theme_provider.dart';
import 'container_block_editor_screen.dart';
import 'slide_block_defaults.dart';
import 'slide_block_editor_dialog.dart';
import 'slide_block_renderer.dart';

/// Full-screen editor for a `columns` block's nested content -- each
/// column holds its OWN list of blocks (any mix of types: images, cards,
/// text, tables, whatever), not just plain text like a table cell. This
/// is what a top-level ListView-of-blocks can't express, which is why
/// columns get this dedicated screen instead of the normal block-edit
/// dialog (see AdminSlideCmsScreen._editBlock's special case for
/// SlideBlockType.columns).
///
/// Deliberately caps columns-within-columns at one level -- a column
/// can't itself contain another columns block (excluded from the
/// per-column "Add Block" bar below) to keep the editing UI and the
/// recursive renderer both tractable; two levels of nested side-by-
/// side columns isn't a layout most slides actually need. A `container`
/// block IS allowed inside a column (and can itself hold a columns
/// block) -- that's a single flat area, not another side-by-side
/// layout, so it doesn't have the same complexity concern.
class ColumnsBlockEditorScreen extends StatefulWidget {
  final SlideBlock block;

  const ColumnsBlockEditorScreen({super.key, required this.block});

  @override
  State<ColumnsBlockEditorScreen> createState() =>
      _ColumnsBlockEditorScreenState();
}

class _ColumnsBlockEditorScreenState extends State<ColumnsBlockEditorScreen> {
  static const int _maxColumns = 4;

  late List<List<SlideBlock>> _columns;
  String? _bg;
  String? _border;
  double _borderWidth = 0;
  double _borderRadius = 14;
  double _padding = 14;
  double _margin = 6;

  @override
  void initState() {
    super.initState();
    _columns = _parseColumns(widget.block.content);
    _bg = widget.block.backgroundColor;
    _border = widget.block.borderColor;
    _borderWidth = widget.block.borderWidth;
    _borderRadius = widget.block.borderRadius ?? 14;
    _padding = widget.block.padding ?? 14;
    _margin = widget.block.marginVertical ?? 6;
  }

  List<List<SlideBlock>> _parseColumns(String content) {
    try {
      final data = json.decode(content) as Map<String, dynamic>;
      final raw = data['columns'] as List? ?? [];
      final parsed = raw.map((col) {
        return (col as List)
            .map((b) => SlideBlock.fromMap(b as Map<String, dynamic>))
            .toList();
      }).toList();
      if (parsed.isNotEmpty) return List<List<SlideBlock>>.from(parsed);
    } catch (_) {}
    return [<SlideBlock>[], <SlideBlock>[]];
  }

  void _save() {
    final content = jsonEncode({
      'columns':
          _columns.map((col) => col.map((b) => b.toMap()).toList()).toList(),
    });
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
      ),
    );
  }

  /// The whole columns block's own box styling (background/outline/
  /// radius/padding/margin) -- opened on demand from the AppBar rather
  /// than permanently occupying space above the column panes, which are
  /// already tight on screen room. See ContainerStyleSection's own doc
  /// comment for why this lives outside the normal block-edit dialog.
  void _openStyleSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: ContainerStyleSection(
              backgroundColor: _bg,
              onBackgroundColorChanged: (val) =>
                  setSheetState(() => _bg = val),
              borderColor: _border,
              onBorderColorChanged: (val) =>
                  setSheetState(() => _border = val),
              borderWidth: _borderWidth,
              onBorderWidthChanged: (val) =>
                  setSheetState(() => _borderWidth = val),
              borderRadius: _borderRadius,
              onBorderRadiusChanged: (val) =>
                  setSheetState(() => _borderRadius = val),
              padding: _padding,
              onPaddingChanged: (val) => setSheetState(() => _padding = val),
              margin: _margin,
              onMarginChanged: (val) => setSheetState(() => _margin = val),
            ),
          ),
        ),
      ),
    );
  }

  void _addColumn() {
    if (_columns.length >= _maxColumns) return;
    setState(() => _columns.add(<SlideBlock>[]));
  }

  void _removeColumn(int colIdx) {
    if (_columns.length <= 1) return;
    setState(() => _columns.removeAt(colIdx));
  }

  void _addBlockToColumn(int colIdx, SlideBlockType type) {
    final defaults = defaultBlockContentFor(type);
    setState(() {
      _columns[colIdx].add(
        applyBannerDefaults(
          SlideBlock(
            id: 'cb_${DateTime.now().millisecondsSinceEpoch}',
            type: type,
            content: defaults.content,
            extra: defaults.extra,
          ),
        ),
      );
    });
  }

  /// A `container` child gets its own dedicated editor screen (see this
  /// class's own doc comment for why); `columns` is handled too even
  /// though the per-column Add Block bar excludes it, in case one ended
  /// up here via raw JSON. Everything else uses the shared dialog.
  Future<void> _editBlockInColumn(int colIdx, int blockIdx) async {
    final block = _columns[colIdx][blockIdx];

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
    if (updated != null && mounted) {
      setState(() => _columns[colIdx][blockIdx] = updated!);
    }
  }

  void _deleteBlockInColumn(int colIdx, int blockIdx) {
    setState(() => _columns[colIdx].removeAt(blockIdx));
  }

  /// Changes what kind of block this is (e.g. paragraph -> text, text ->
  /// card) via the type label's own tap target -- see
  /// pickSlideBlockType's doc comment for why content/extra/caption/
  /// style fields are all left exactly as they were.
  Future<void> _changeBlockTypeInColumn(int colIdx, int blockIdx) async {
    final block = _columns[colIdx][blockIdx];
    final newType = await pickSlideBlockType(context, block.type);
    if (newType == null || !mounted) return;
    setState(() => _columns[colIdx][blockIdx] = block.copyWith(type: newType));
  }

  void _reorderInColumn(int colIdx, int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _columns[colIdx].removeAt(oldIndex);
      _columns[colIdx].insert(newIndex, moved);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Columns (${_columns.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.style_rounded),
            tooltip: 'Container Style (background/outline/padding for the '
                'whole columns block)',
            onPressed: _openStyleSheet,
          ),
          IconButton(
            icon: const Icon(Icons.add_box_rounded),
            tooltip: 'Add Column',
            onPressed: _columns.length < _maxColumns ? _addColumn : null,
          ),
          const SizedBox(width: 4),
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
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < _columns.length; i++)
            Expanded(child: _buildColumnPane(context, i, isDark)),
        ],
      ),
    );
  }

  Widget _buildColumnPane(BuildContext context, int colIdx, bool isDark) {
    final blocks = _columns[colIdx];
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                Text(
                  'Column ${colIdx + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: Colors.redAccent),
                  tooltip: 'Remove Column',
                  onPressed:
                      _columns.length > 1 ? () => _removeColumn(colIdx) : null,
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: SlideBlockType.values
                  // A column can't itself contain another columns block --
                  // see this class's own doc comment for why.
                  .where((t) => t != SlideBlockType.columns)
                  .map((type) {
                return Padding(
                  padding: const EdgeInsets.only(right: 4.0),
                  child: IconButton(
                    icon: Icon(iconForSlideBlockType(type), size: 18),
                    tooltip: 'Add ${displayNameForSlideBlockType(type)}',
                    onPressed: () => _addBlockToColumn(colIdx, type),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: blocks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'No blocks yet -- use the icons above to add one.',
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: blocks.length,
                    onReorder: (oldIndex, newIndex) =>
                        _reorderInColumn(colIdx, oldIndex, newIndex),
                    itemBuilder: (context, blockIdx) {
                      final b = blocks[blockIdx];
                      return Card(
                        key: ValueKey(b.id),
                        margin: const EdgeInsets.only(bottom: 8),
                        color:
                            isDark ? const Color(0xFF0F172A) : Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ReorderableDragStartListener(
                                    index: blockIdx,
                                    child: const Padding(
                                      padding: EdgeInsets.only(right: 6.0),
                                      child: Icon(
                                        Icons.drag_indicator_rounded,
                                        size: 16,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () =>
                                          _changeBlockTypeInColumn(colIdx, blockIdx),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            displayNameForSlideBlockType(b.type),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF6366F1),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.swap_horiz_rounded,
                                            size: 12,
                                            color: Color(0xFF6366F1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded,
                                        size: 14),
                                    onPressed: () =>
                                        _editBlockInColumn(colIdx, blockIdx),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_rounded,
                                        size: 14, color: Colors.red),
                                    onPressed: () =>
                                        _deleteBlockInColumn(colIdx, blockIdx),
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
          ),
        ],
      ),
    );
  }
}
