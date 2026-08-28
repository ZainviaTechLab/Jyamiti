import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../domain/models/slide_deck_models.dart';
import 'slide_color_utils.dart';

/// The block-edit dialog -- content/extra/caption fields per block type,
/// plus (banner only) the Banner Layout section. A standalone top-level
/// function (not a method on any one screen's State) so it's reusable
/// from both AdminSlideCmsScreen (editing a block on the active slide)
/// and ColumnsBlockEditorScreen (editing a block nested inside one
/// column) -- both just need "edit this one block, get back the edited
/// version or null if cancelled" and can each decide for themselves where
/// the result actually gets applied.
///
/// There's no generic background/text/outline color UI that applies to
/// every block type anymore -- that was removed. Banner, card, and text
/// each keep their own background/text/outline controls (inside Banner
/// Layout / Card Style / Text Style below) since coloring IS what those
/// three fundamentally are (a colored bar; a bordered box; freeform
/// styled text), not optional styling on top of some other content the
/// way it would be for a heading or a paragraph.
Future<SlideBlock?> showSlideBlockEditorDialog(
  BuildContext context,
  SlideBlock block,
) {
  final contentCtrl = TextEditingController(text: block.content);
  final extraCtrl = TextEditingController(text: block.extra ?? '');
  final captionCtrl = TextEditingController(text: block.caption ?? '');

  // Layout fields -- currently only shown/meaningful for the banner
  // block type (see SlideBlockRenderer._buildBannerBlock), but stored on
  // every SlideBlock generally (see that model's own doc comment), so
  // this section is gated on block.type below rather than living in a
  // banner-only dialog.
  double layoutPadding = block.padding ?? 16;
  double layoutMarginVertical = block.marginVertical ?? 12;
  double layoutFontSize = block.fontSize ?? 20;
  String layoutHorizontalAlign = block.horizontalAlign ?? 'center';
  String layoutVerticalAlign = block.verticalAlign ?? 'center';
  String? bannerBg = block.backgroundColor;
  String? bannerText = block.textColor;
  String? bannerBorder = block.borderColor;
  double bannerBorderWidth = block.borderWidth;

  // Card's own style fields -- see SlideBlockRenderer._buildCardBlock,
  // which reads these same 4 fields directly (and, notably, defaults
  // borderWidth to 2.0 rather than 0 when unset, since a card is always
  // drawn with a visible border -- mirrored here so the slider's initial
  // position matches what's actually rendered).
  String? cardBg = block.backgroundColor;
  String? cardText = block.textColor;
  String? cardBorder = block.borderColor;
  double cardBorderWidth = block.borderWidth > 0 ? block.borderWidth : 2.0;

  // Text's own style fields -- see SlideBlockRenderer._buildTextBlock,
  // which reads these plus the bold/italic/underline/strikethrough flags
  // below. Unlike card, text's background/border stay genuinely optional
  // (null means "just text, no box"), so borderWidth isn't forced to a
  // nonzero default the way card's is.
  String? textBg = block.backgroundColor;
  String? textFg = block.textColor;
  String? textBorder = block.borderColor;
  double textBorderWidth = block.borderWidth;
  double textFontSize = block.fontSize ?? 16;
  String textHorizontalAlign = block.horizontalAlign ?? 'left';
  bool textBold = block.bold;
  bool textItalic = block.italic;
  bool textUnderline = block.underline;
  bool textStrikethrough = block.strikethrough;

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
                              block.type == SlideBlockType.card ||
                              block.type == SlideBlockType.text
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
                                    : block.type == SlideBlockType.banner
                                        ? 'Banner Title'
                                        : block.type == SlideBlockType.text
                                            ? 'Text Content'
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
              if (block.type == SlideBlockType.card) ...[
                const SizedBox(height: 16),
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Card Style',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 10),
                SlideColorPickerField(
                  label: 'Background',
                  initialHex: cardBg,
                  onChanged: (val) => cardBg = val,
                ),
                const SizedBox(height: 14),
                SlideColorPickerField(
                  label: 'Text Color',
                  initialHex: cardText,
                  onChanged: (val) => cardText = val,
                ),
                const SizedBox(height: 14),
                SlideColorPickerField(
                  label: 'Outline',
                  initialHex: cardBorder,
                  onChanged: (val) => cardBorder = val,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Outline Width', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: cardBorderWidth.clamp(0, 6),
                        min: 0,
                        max: 6,
                        divisions: 12,
                        label: cardBorderWidth.toStringAsFixed(1),
                        onChanged: (val) =>
                            setDialogState(() => cardBorderWidth = val),
                      ),
                    ),
                  ],
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
              if (block.type == SlideBlockType.banner) ...[
                const SizedBox(height: 16),
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Banner Layout',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 10),
                SlideColorPickerField(
                  label: 'Background',
                  initialHex: bannerBg,
                  onChanged: (val) => bannerBg = val,
                ),
                const SizedBox(height: 14),
                SlideColorPickerField(
                  label: 'Text Color',
                  initialHex: bannerText,
                  onChanged: (val) => bannerText = val,
                ),
                const SizedBox(height: 14),
                SlideColorPickerField(
                  label: 'Outline',
                  initialHex: bannerBorder,
                  onChanged: (val) => bannerBorder = val,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Outline Width', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: bannerBorderWidth.clamp(0, 6),
                        min: 0,
                        max: 6,
                        divisions: 12,
                        label: bannerBorderWidth.toStringAsFixed(1),
                        onChanged: (val) =>
                            setDialogState(() => bannerBorderWidth = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Padding', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: layoutPadding.clamp(0, 48),
                        min: 0,
                        max: 48,
                        divisions: 24,
                        label: layoutPadding.toStringAsFixed(0),
                        onChanged: (val) =>
                            setDialogState(() => layoutPadding = val),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Margin', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: layoutMarginVertical.clamp(0, 48),
                        min: 0,
                        max: 48,
                        divisions: 24,
                        label: layoutMarginVertical.toStringAsFixed(0),
                        onChanged: (val) => setDialogState(
                            () => layoutMarginVertical = val),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Font Size', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: layoutFontSize.clamp(12, 48),
                        min: 12,
                        max: 48,
                        divisions: 36,
                        label: layoutFontSize.toStringAsFixed(0),
                        onChanged: (val) =>
                            setDialogState(() => layoutFontSize = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('Horizontal Alignment',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'left', label: Text('Left')),
                    ButtonSegment(value: 'center', label: Text('Center')),
                    ButtonSegment(value: 'right', label: Text('Right')),
                  ],
                  selected: {layoutHorizontalAlign},
                  onSelectionChanged: (sel) => setDialogState(
                      () => layoutHorizontalAlign = sel.first),
                ),
                const SizedBox(height: 10),
                const Text('Vertical Alignment',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'top', label: Text('Top')),
                    ButtonSegment(value: 'center', label: Text('Center')),
                    ButtonSegment(value: 'bottom', label: Text('Bottom')),
                  ],
                  selected: {layoutVerticalAlign},
                  onSelectionChanged: (sel) =>
                      setDialogState(() => layoutVerticalAlign = sel.first),
                ),
              ],
              if (block.type == SlideBlockType.text) ...[
                const SizedBox(height: 16),
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Text Style',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 10),
                SlideColorPickerField(
                  label: 'Text Color',
                  initialHex: textFg,
                  onChanged: (val) => textFg = val,
                ),
                const SizedBox(height: 14),
                SlideColorPickerField(
                  label: 'Background (optional)',
                  initialHex: textBg,
                  onChanged: (val) => textBg = val,
                ),
                const SizedBox(height: 14),
                SlideColorPickerField(
                  label: 'Outline (optional)',
                  initialHex: textBorder,
                  onChanged: (val) => textBorder = val,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Outline Width', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: textBorderWidth.clamp(0, 6),
                        min: 0,
                        max: 6,
                        divisions: 12,
                        label: textBorderWidth.toStringAsFixed(1),
                        onChanged: (val) =>
                            setDialogState(() => textBorderWidth = val),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Font Size', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: textFontSize.clamp(10, 48),
                        min: 10,
                        max: 48,
                        divisions: 38,
                        label: textFontSize.toStringAsFixed(0),
                        onChanged: (val) =>
                            setDialogState(() => textFontSize = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('Horizontal Alignment',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'left', label: Text('Left')),
                    ButtonSegment(value: 'center', label: Text('Center')),
                    ButtonSegment(value: 'right', label: Text('Right')),
                    ButtonSegment(value: 'justify', label: Text('Justify')),
                  ],
                  selected: {textHorizontalAlign},
                  onSelectionChanged: (sel) =>
                      setDialogState(() => textHorizontalAlign = sel.first),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Bold'),
                      selected: textBold,
                      onSelected: (val) =>
                          setDialogState(() => textBold = val),
                    ),
                    FilterChip(
                      label: const Text('Italic'),
                      selected: textItalic,
                      onSelected: (val) =>
                          setDialogState(() => textItalic = val),
                    ),
                    FilterChip(
                      label: const Text('Underline'),
                      selected: textUnderline,
                      onSelected: (val) =>
                          setDialogState(() => textUnderline = val),
                    ),
                    FilterChip(
                      label: const Text('Strikethrough'),
                      selected: textStrikethrough,
                      onSelected: (val) =>
                          setDialogState(() => textStrikethrough = val),
                    ),
                  ],
                ),
              ],
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
                backgroundColor: block.type == SlideBlockType.banner
                    ? bannerBg
                    : block.type == SlideBlockType.card
                        ? cardBg
                        : block.type == SlideBlockType.text
                            ? textBg
                            : null,
                clearBackgroundColor:
                    (block.type == SlideBlockType.banner && bannerBg == null) ||
                        (block.type == SlideBlockType.card && cardBg == null) ||
                        (block.type == SlideBlockType.text && textBg == null),
                textColor: block.type == SlideBlockType.banner
                    ? bannerText
                    : block.type == SlideBlockType.card
                        ? cardText
                        : block.type == SlideBlockType.text
                            ? textFg
                            : null,
                clearTextColor: (block.type == SlideBlockType.banner &&
                        bannerText == null) ||
                    (block.type == SlideBlockType.card && cardText == null) ||
                    (block.type == SlideBlockType.text && textFg == null),
                borderColor: block.type == SlideBlockType.banner
                    ? bannerBorder
                    : block.type == SlideBlockType.card
                        ? cardBorder
                        : block.type == SlideBlockType.text
                            ? textBorder
                            : null,
                clearBorderColor: (block.type == SlideBlockType.banner &&
                        bannerBorder == null) ||
                    (block.type == SlideBlockType.card && cardBorder == null) ||
                    (block.type == SlideBlockType.text && textBorder == null),
                borderWidth: block.type == SlideBlockType.banner
                    ? bannerBorderWidth
                    : block.type == SlideBlockType.card
                        ? cardBorderWidth
                        : block.type == SlideBlockType.text
                            ? textBorderWidth
                            : null,
                padding: block.type == SlideBlockType.banner
                    ? layoutPadding
                    : null,
                marginVertical: block.type == SlideBlockType.banner
                    ? layoutMarginVertical
                    : null,
                fontSize: block.type == SlideBlockType.banner
                    ? layoutFontSize
                    : block.type == SlideBlockType.text
                        ? textFontSize
                        : null,
                horizontalAlign: block.type == SlideBlockType.banner
                    ? layoutHorizontalAlign
                    : block.type == SlideBlockType.text
                        ? textHorizontalAlign
                        : null,
                verticalAlign: block.type == SlideBlockType.banner
                    ? layoutVerticalAlign
                    : null,
                bold: block.type == SlideBlockType.text ? textBold : null,
                italic: block.type == SlideBlockType.text ? textItalic : null,
                underline:
                    block.type == SlideBlockType.text ? textUnderline : null,
                strikethrough: block.type == SlideBlockType.text
                    ? textStrikethrough
                    : null,
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
