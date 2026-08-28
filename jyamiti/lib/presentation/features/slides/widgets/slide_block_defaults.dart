import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../domain/models/slide_deck_models.dart';

/// The icon shown for each block type in "Add Block" bars and block-list
/// cards -- a top-level function (not a method on any one screen's State)
/// so both AdminSlideCmsScreen and ColumnsBlockEditorScreen can share it
/// rather than keeping two copies of the same switch in sync.
IconData iconForSlideBlockType(SlideBlockType type) {
  switch (type) {
    case SlideBlockType.heading:
      return Icons.title_rounded;
    case SlideBlockType.subheading:
      return Icons.text_fields_rounded;
    case SlideBlockType.paragraph:
      return Icons.segment_rounded;
    case SlideBlockType.code:
      return Icons.code_rounded;
    case SlideBlockType.bulletList:
      return Icons.format_list_bulleted_rounded;
    case SlideBlockType.callout:
      return Icons.info_outline_rounded;
    case SlideBlockType.imageUrl:
      return Icons.image_rounded;
    case SlideBlockType.math:
      return Icons.functions_rounded;
    case SlideBlockType.svg:
      return Icons.polyline_rounded;
    case SlideBlockType.table:
      return Icons.table_chart_rounded;
    case SlideBlockType.video:
      return Icons.smart_display_rounded;
    case SlideBlockType.card:
      return Icons.crop_square_rounded;
    case SlideBlockType.columns:
      return Icons.view_column_rounded;
    case SlideBlockType.banner:
      return Icons.view_agenda_rounded;
    case SlideBlockType.text:
      return Icons.format_color_text_rounded;
  }
}

/// Style defaults specific to the `banner` block type (background/text
/// color, padding, margin, font size, alignment) -- applied via
/// `.copyWith(...)` on top of whatever `defaultBlockContentFor` returns,
/// at both call sites that create a fresh block (AdminSlideCmsScreen's
/// Add Block bar and ColumnsBlockEditorScreen's per-column Add Block
/// bar). Kept separate from `defaultBlockContentFor`'s record rather than
/// widening that record's shape for every other block type just for
/// banner's sake.
SlideBlock applyBannerDefaults(SlideBlock block) {
  if (block.type != SlideBlockType.banner) return block;
  return block.copyWith(
    backgroundColor: 'FFF59E0B',
    textColor: 'FF000000',
    padding: 16,
    marginVertical: 12,
    fontSize: 20,
    horizontalAlign: 'center',
    verticalAlign: 'center',
  );
}

/// A freshly-added block's starting content/extra -- same reasoning as
/// [iconForSlideBlockType] for being a shared top-level function rather
/// than a method duplicated per screen.
({String content, String? extra}) defaultBlockContentFor(
  SlideBlockType type,
) {
  switch (type) {
    case SlideBlockType.heading:
      return (content: 'New Section Title', extra: null);
    case SlideBlockType.subheading:
      return (content: 'Sub-topic Header', extra: null);
    case SlideBlockType.paragraph:
      return (
        content: 'Explanation paragraph text for students...',
        extra: null
      );
    case SlideBlockType.code:
      return (
        content:
            '// Write code snippet here\nvoid main() {\n  print("Hello World!");\n}',
        extra: 'dart',
      );
    case SlideBlockType.bulletList:
      return (
        content: 'First Key Point\nSecond Key Point\nThird Key Point',
        extra: null,
      );
    case SlideBlockType.callout:
      return (
        content: 'Important note or tip for students.',
        extra: 'info',
      );
    case SlideBlockType.imageUrl:
      return (
        content:
            'https://images.unsplash.com/photo-1635070041078-e363dbe005cb?w=800',
        extra: null,
      );
    case SlideBlockType.math:
      return (content: r'a^2 + b^2 = c^2', extra: null);
    case SlideBlockType.svg:
      return (
        content:
            "<svg viewBox='0 0 400 200' xmlns='http://www.w3.org/2000/svg'>\n  <rect width='400' height='200' fill='#0b2240' rx='12'/>\n  <circle cx='200' cy='100' r='50' fill='#6366f1'/>\n  <text x='200' y='105' fill='#ffffff' font-size='16' text-anchor='middle' font-weight='bold'>SVG Diagram</text>\n</svg>",
        extra: null,
      );
    case SlideBlockType.table:
      // See SlideBlockRenderer._buildTableBlock's doc comment -- table
      // content is JSON-encoded {headers, rows}, not plain text.
      return (
        content: jsonEncode({
          'headers': ['Column A', 'Column B'],
          'rows': [
            ['', ''],
            ['', ''],
          ],
        }),
        extra: null,
      );
    case SlideBlockType.video:
      return (content: '', extra: null);
    case SlideBlockType.card:
      return (
        content:
            '7 = 3 + 4\n10 = 1 + 2 + 3 + 4\n12 = 3 + 4 + 5\n15 = 7 + 8\n= 4 + 5 + 6\n= 1 + 2 + 3 + 4 + 5',
        extra: null,
      );
    case SlideBlockType.columns:
      // See SlideBlockRenderer._buildColumnsBlock's doc comment -- a
      // columns block's content is JSON-encoded {columns: [[blockMap,
      // ...], [...]]}, one inner list of block maps per column. Starts
      // with 2 empty columns.
      return (
        content: jsonEncode({
          'columns': [[], []],
        }),
        extra: null,
      );
    case SlideBlockType.banner:
      return (content: 'New Banner Section Title', extra: null);
    case SlideBlockType.text:
      return (
        content: 'Styled text -- color, size, alignment and formatting '
            'are all adjustable in Text Style below.',
        extra: null,
      );
  }
}
