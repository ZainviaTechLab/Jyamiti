import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../domain/models/slide_deck_models.dart';
import 'slide_color_utils.dart';

/// The block-edit dialog -- content/extra/caption fields per block type,
/// plus the shared Style section (background/text/outline color +
/// outline width) that applies to every block type. A standalone
/// top-level function (not a method on any one screen's State) so it's
/// reusable from both AdminSlideCmsScreen (editing a block on the active
/// slide) and ColumnsBlockEditorScreen (editing a block nested inside one
/// column) -- both just need "edit this one block, get back the edited
/// version or null if cancelled" and can each decide for themselves where
/// the result actually gets applied.
Future<SlideBlock?> showSlideBlockEditorDialog(
  BuildContext context,
  SlideBlock block,
) {
  final contentCtrl = TextEditingController(text: block.content);
  final extraCtrl = TextEditingController(text: block.extra ?? '');
  final captionCtrl = TextEditingController(text: block.caption ?? '');

  String? styleBg = block.backgroundColor;
  String? styleText = block.textColor;
  String? styleBorder = block.borderColor;
  double styleBorderWidth = block.borderWidth;

  // Table editing works on a structured header/row list rather than raw
  // JSON -- parsed once here, re-serialized back into block.content on
  // Save (see SlideBlockRenderer._buildTableBlock's doc comment for the
  // JSON shape).
  List<String> tableHeaders = ['Column A', 'Column B'];
  List<List<String>> tableRows = [
    ['', '']
  ];
  if (block.type == SlideBlockType.table) {
    try {
      final data = json.decode(block.content) as Map<String, dynamic>;
      tableHeaders =
          (data['headers'] as List? ?? []).map((e) => e.toString()).toList();
      tableRows = (data['rows'] as List? ?? [])
          .map((r) => (r as List).map((c) => c.toString()).toList())
          .toList();
    } catch (_) {}
    if (tableHeaders.isEmpty) tableHeaders = ['Column A', 'Column B'];
    if (tableRows.isEmpty) {
      tableRows = [List.filled(tableHeaders.length, '')];
    }
  }

  return showDialog<SlideBlock>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text('Edit ${block.type.name.toUpperCase()} Block'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (block.type == SlideBlockType.table)
                _buildTableEditor(
                  headers: tableHeaders,
                  rows: tableRows,
                  onChanged: () => setDialogState(() {}),
                )
              else
                TextField(
                  controller: contentCtrl,
                  maxLines:
                      block.type == SlideBlockType.code ||
                              block.type == SlideBlockType.paragraph ||
                              block.type == SlideBlockType.bulletList ||
                              block.type == SlideBlockType.svg ||
                              block.type == SlideBlockType.card
                          ? 6
                          : 2,
                  decoration: InputDecoration(
                    labelText: block.type == SlideBlockType.svg
                        ? 'SVG XML Code'
                        : block.type == SlideBlockType.card
                            ? 'Card Content (Text or LaTeX equations)'
                            : block.type == SlideBlockType.video
                                ? 'YouTube URL or Video ID'
                                : block.type == SlideBlockType.imageUrl
                                    ? 'Image URL'
                                    : 'Content',
                    border: const OutlineInputBorder(),
                  ),
                ),
              if (block.type == SlideBlockType.imageUrl ||
                  block.type == SlideBlockType.card) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: captionCtrl,
                  decoration: InputDecoration(
                    labelText: block.type == SlideBlockType.card
                        ? 'Card Title / Header (e.g. Set 1, Explore)'
                        : 'Caption (optional, shown below the image)',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              if (block.type == SlideBlockType.svg ||
                  block.type == SlideBlockType.card) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: [
                    'full',
                    'original',
                    'boxed',
                    'compact',
                    'small',
                  ].contains(extraCtrl.text.toLowerCase().trim())
                      ? extraCtrl.text.toLowerCase().trim()
                      : (block.type == SlideBlockType.card ? 'boxed' : 'full'),
                  decoration: const InputDecoration(
                    labelText: 'Display Width Mode',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'boxed',
                      child: Text('Boxed Card (85% Width Frame)'),
                    ),
                    DropdownMenuItem(
                      value: 'full',
                      child: Text('Full Width (Edge-to-Edge)'),
                    ),
                    DropdownMenuItem(
                      value: 'compact',
                      child: Text('Compact (75% Width)'),
                    ),
                    DropdownMenuItem(
                      value: 'small',
                      child: Text('Small (50% Width)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      extraCtrl.text = val;
                    }
                  },
                ),
              ],
              if (block.type == SlideBlockType.code ||
                  block.type == SlideBlockType.callout) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: extraCtrl,
                  decoration: InputDecoration(
                    labelText: block.type == SlideBlockType.code
                        ? 'Language (e.g. dart, python, html)'
                        : 'Callout Type (info, tip, warning)',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Style (optional)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(height: 10),
              SlideColorPickerField(
                label: 'Background',
                initialHex: styleBg,
                onChanged: (val) => styleBg = val,
              ),
              const SizedBox(height: 14),
              SlideColorPickerField(
                label: 'Text Color',
                initialHex: styleText,
                onChanged: (val) => styleText = val,
              ),
              const SizedBox(height: 14),
              SlideColorPickerField(
                label: 'Outline',
                initialHex: styleBorder,
                onChanged: (val) => styleBorder = val,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Outline Width', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Slider(
                      value: styleBorderWidth.clamp(0, 6),
                      min: 0,
                      max: 6,
                      divisions: 12,
                      label: styleBorderWidth.toStringAsFixed(1),
                      onChanged: (val) =>
                          setDialogState(() => styleBorderWidth = val),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newContent = block.type == SlideBlockType.table
                  ? jsonEncode({'headers': tableHeaders, 'rows': tableRows})
                  : contentCtrl.text;
              final updated = block.copyWith(
                content: newContent,
                extra: extraCtrl.text.isNotEmpty ? extraCtrl.text : null,
                clearExtra: extraCtrl.text.isEmpty,
                caption:
                    captionCtrl.text.isNotEmpty ? captionCtrl.text : null,
                clearCaption: captionCtrl.text.isEmpty,
                backgroundColor: styleBg,
                clearBackgroundColor: styleBg == null,
                textColor: styleText,
                clearTextColor: styleText == null,
                borderColor: styleBorder,
                clearBorderColor: styleBorder == null,
                borderWidth: styleBorderWidth,
              );
              Navigator.pop(ctx, updated);
            },
            child: const Text('Save Block'),
          ),
        ],
      ),
    ),
  );
}

/// A structured header/row editor for table blocks, used in place of a
/// raw-JSON text field -- `headers`/`rows` are mutated in place;
/// `onChanged` triggers a dialog rebuild (via the caller's
/// setDialogState) after any structural change (add/remove row/column).
/// Cell edits themselves mutate directly without triggering a rebuild,
/// since nothing else on screen depends on a cell's live value.
Widget _buildTableEditor({
  required List<String> headers,
  required List<List<String>> rows,
  required VoidCallback onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Columns',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      const SizedBox(height: 8),
      ...List.generate(headers.length, (colIdx) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: headers[colIdx],
                  decoration: InputDecoration(
                    labelText: 'Column ${colIdx + 1}',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (val) => headers[colIdx] = val,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.remove_circle_outline_rounded,
                  size: 18,
                  color: Colors.red,
                ),
                onPressed: headers.length > 1
                    ? () {
                        headers.removeAt(colIdx);
                        for (final row in rows) {
                          if (colIdx < row.length) row.removeAt(colIdx);
                        }
                        onChanged();
                      }
                    : null,
              ),
            ],
          ),
        );
      }),
      TextButton.icon(
        onPressed: () {
          headers.add('Column ${headers.length + 1}');
          for (final row in rows) {
            row.add('');
          }
          onChanged();
        },
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('Add Column'),
      ),
      const Divider(),
      const Text(
        'Rows',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      const SizedBox(height: 8),
      ...List.generate(rows.length, (rowIdx) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(headers.length, (colIdx) {
                    final cellValue = colIdx < rows[rowIdx].length
                        ? rows[rowIdx][colIdx]
                        : '';
                    return SizedBox(
                      width: 120,
                      child: TextFormField(
                        initialValue: cellValue,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: headers[colIdx],
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          while (rows[rowIdx].length <= colIdx) {
                            rows[rowIdx].add('');
                          }
                          rows[rowIdx][colIdx] = val;
                        },
                      ),
                    );
                  }),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.remove_circle_outline_rounded,
                  size: 18,
                  color: Colors.red,
                ),
                onPressed: rows.length > 1
                    ? () {
                        rows.removeAt(rowIdx);
                        onChanged();
                      }
                    : null,
              ),
            ],
          ),
        );
      }),
      TextButton.icon(
        onPressed: () {
          rows.add(List.generate(headers.length, (_) => ''));
          onChanged();
        },
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('Add Row'),
      ),
    ],
  );
}
