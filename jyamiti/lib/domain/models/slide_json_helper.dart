import 'dart:convert';
import 'slide_deck_models.dart';

enum SlideImportPlacement {
  appendToEnd,
  insertAfterActive,
  replaceActive,
  replaceAll,
}

class SlideImportParseResult {
  final bool isSuccess;
  final String? errorMessage;
  final List<SlideItem> slides;
  final String? deckTitle;
  final String? deckDescription;
  final String? courseName;

  const SlideImportParseResult({
    required this.isSuccess,
    this.errorMessage,
    this.slides = const [],
    this.deckTitle,
    this.deckDescription,
    this.courseName,
  });

  factory SlideImportParseResult.failure(String message) {
    return SlideImportParseResult(
      isSuccess: false,
      errorMessage: message,
      slides: const [],
    );
  }

  factory SlideImportParseResult.success({
    required List<SlideItem> slides,
    String? deckTitle,
    String? deckDescription,
    String? courseName,
  }) {
    return SlideImportParseResult(
      isSuccess: true,
      slides: slides,
      deckTitle: deckTitle,
      deckDescription: deckDescription,
      courseName: courseName,
    );
  }
}

class SlideJsonHelper {
  static const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');

  /// Parses a raw JSON string into a [SlideImportParseResult].
  static SlideImportParseResult parseJson(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return SlideImportParseResult.failure('JSON input is empty.');
    }

    dynamic decoded;
    try {
      decoded = json.decode(trimmed);
    } catch (e) {
      return SlideImportParseResult.failure('Invalid JSON syntax: $e');
    }

    try {
      if (decoded is List) {
        // List of slides
        final slides = _parseSlideList(decoded);
        if (slides.isEmpty) {
          return SlideImportParseResult.failure(
            'The JSON array did not contain any valid slides.',
          );
        }
        return SlideImportParseResult.success(slides: slides);
      } else if (decoded is Map<String, dynamic>) {
        // Could be a full SlideDeck OR a single SlideItem OR an object containing a 'slides' key
        if (decoded.containsKey('slides') && decoded['slides'] is List) {
          final slides = _parseSlideList(decoded['slides'] as List<dynamic>);
          return SlideImportParseResult.success(
            slides: slides,
            deckTitle: decoded['title']?.toString(),
            deckDescription: decoded['description']?.toString(),
            courseName: decoded['courseName']?.toString(),
          );
        } else {
          // Single slide item
          final slide = _parseSingleSlide(decoded, 0);
          return SlideImportParseResult.success(slides: [slide]);
        }
      } else {
        return SlideImportParseResult.failure(
          'Root JSON must be an object { ... } or an array [ ... ].',
        );
      }
    } catch (e) {
      return SlideImportParseResult.failure('Failed to parse slide data: $e');
    }
  }

  /// Parses a list of slide maps
  static List<SlideItem> _parseSlideList(List<dynamic> rawList) {
    final List<SlideItem> result = [];
    for (int i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is Map<String, dynamic>) {
        result.add(_parseSingleSlide(item, i));
      }
    }
    return result;
  }

  /// Parses a single slide map with fallback mechanisms and normalization
  static SlideItem _parseSingleSlide(
    Map<String, dynamic> map,
    int fallbackIndex,
  ) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final slideId = map['id']?.toString().isNotEmpty == true
        ? map['id'].toString()
        : 'slide_${now}_$fallbackIndex';

    final title =
        map['title']?.toString() ??
        map['heading']?.toString() ??
        'Slide ${fallbackIndex + 1}';

    final theme = _normalizeTheme(map['theme']?.toString());
    final enableWhiteboard = map['enableWhiteboard'] != false;

    // Parse blocks
    List<SlideBlock> blocks = [];
    if (map['blocks'] is List) {
      final rawBlocks = map['blocks'] as List<dynamic>;
      for (int b = 0; b < rawBlocks.length; b++) {
        final bItem = rawBlocks[b];
        if (bItem is Map<String, dynamic>) {
          blocks.add(_parseSingleBlock(bItem, fallbackIndex, b));
        }
      }
    }

    // If blocks list was empty, provide a default paragraph block if content exists in root
    if (blocks.isEmpty) {
      final fallbackContent =
          map['content']?.toString() ?? map['body']?.toString();
      if (fallbackContent != null && fallbackContent.isNotEmpty) {
        blocks.add(
          SlideBlock(
            id: 'b_${now}_${fallbackIndex}_0',
            type: SlideBlockType.paragraph,
            content: fallbackContent,
          ),
        );
      } else {
        blocks.add(
          SlideBlock(
            id: 'b_${now}_${fallbackIndex}_0',
            type: SlideBlockType.heading,
            content: title,
          ),
        );
      }
    }

    // Parse Quiz
    SlideQuiz? quiz;
    if (map['quiz'] != null && map['quiz'] is Map<String, dynamic>) {
      quiz = _parseQuiz(map['quiz'] as Map<String, dynamic>);
    }

    final backgroundType = SlideBackgroundType.values.firstWhere(
      (e) =>
          e.name.toLowerCase() ==
          (map['backgroundType'] ?? '').toString().toLowerCase(),
      orElse: () => SlideBackgroundType.theme,
    );

    return SlideItem(
      id: slideId,
      slideIndex: fallbackIndex,
      title: title,
      blocks: blocks,
      theme: theme,
      quiz: quiz,
      enableWhiteboard: enableWhiteboard,
      backgroundType: backgroundType,
      backgroundColor: map['backgroundColor']?.toString(),
      backgroundColor2: map['backgroundColor2']?.toString(),
      backgroundImageUrl: map['backgroundImageUrl']?.toString(),
    );
  }

  /// Parses a single block with type alias recognition
  static SlideBlock _parseSingleBlock(
    Map<String, dynamic> map,
    int slideIndex,
    int blockIndex,
  ) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final blockId = map['id']?.toString().isNotEmpty == true
        ? map['id'].toString()
        : 'b_${now}_${slideIndex}_$blockIndex';

    final rawType = (map['type'] ?? 'paragraph')
        .toString()
        .toLowerCase()
        .trim();
    final content =
        map['content']?.toString() ??
        map['text']?.toString() ??
        map['code']?.toString() ??
        map['latex']?.toString() ??
        map['svg']?.toString() ??
        map['url']?.toString() ??
        '';

    var type = _resolveBlockType(rawType);
    if (content.trim().startsWith('<svg') && type == SlideBlockType.paragraph) {
      type = SlideBlockType.svg;
    }

    // Table content is JSON-encoded {headers, rows} inside `content` (see
    // SlideBlockRenderer._buildTableBlock's doc comment) -- but a hand-
    // written import is more likely to put `headers`/`rows` directly at
    // the block's top level rather than pre-stringify them, so accept
    // that shape too when `content` itself didn't already resolve to
    // something usable.
    String resolvedContent = content;
    if (type == SlideBlockType.table &&
        content.isEmpty &&
        (map['headers'] is List || map['rows'] is List)) {
      resolvedContent = jsonEncode({
        'headers': map['headers'] ?? [],
        'rows': map['rows'] ?? [],
      });
    } else if (type == SlideBlockType.video && content.isEmpty) {
      resolvedContent =
          map['videoUrl']?.toString() ??
          map['youtube']?.toString() ??
          map['videoId']?.toString() ??
          '';
    } else if (type == SlideBlockType.columns &&
        content.isEmpty &&
        map['columns'] is List) {
      // Same idea as table above, one level deeper: `columns` is a list
      // of lists of raw block maps -- each nested block is parsed through
      // this SAME function (recursively) so it gets normal id generation
      // and type-alias resolution, then re-serialized into the JSON shape
      // SlideBlockRenderer._buildColumnsBlock expects.
      final rawColumns = map['columns'] as List;
      final parsedColumns = <List<Map<String, dynamic>>>[];
      for (final colEntry in rawColumns) {
        final List<Map<String, dynamic>> colBlocks = [];
        if (colEntry is List) {
          for (int b = 0; b < colEntry.length; b++) {
            final bItem = colEntry[b];
            if (bItem is Map<String, dynamic>) {
              colBlocks.add(_parseSingleBlock(bItem, slideIndex, b).toMap());
            }
          }
        }
        parsedColumns.add(colBlocks);
      }
      resolvedContent = jsonEncode({'columns': parsedColumns});
    } else if (type == SlideBlockType.container &&
        content.isEmpty &&
        map['children'] is List) {
      // Same idea as columns above, one level shallower: `children` is
      // a flat list of raw block maps (a single area, not columns-of-
      // lists) -- each nested block is parsed through this SAME
      // function (recursively, so a container can hold another
      // container or a columns block) then re-serialized into the JSON
      // shape SlideBlockRenderer._buildContainerBlock expects.
      final rawChildren = map['children'] as List;
      final parsedChildren = <Map<String, dynamic>>[];
      for (int b = 0; b < rawChildren.length; b++) {
        final bItem = rawChildren[b];
        if (bItem is Map<String, dynamic>) {
          parsedChildren.add(_parseSingleBlock(bItem, slideIndex, b).toMap());
        }
      }
      resolvedContent = jsonEncode({'children': parsedChildren});
    }

    final extra = map['extra']?.toString() ?? map['language']?.toString();
    final caption = map['caption']?.toString();
    final backgroundColor = map['backgroundColor']?.toString();
    final textColor = map['textColor']?.toString();
    final borderColor = map['borderColor']?.toString();
    final borderWidth = (map['borderWidth'] as num?)?.toDouble() ?? 0;
    final padding = (map['padding'] as num?)?.toDouble();
    final marginVertical = (map['marginVertical'] as num?)?.toDouble();
    final fontSize = (map['fontSize'] as num?)?.toDouble();
    final horizontalAlign = map['horizontalAlign']?.toString();
    final verticalAlign = map['verticalAlign']?.toString();
    final minHeight = (map['minHeight'] as num?)?.toDouble();
    final bold = map['bold'] == true;
    final italic = map['italic'] == true;
    final underline = map['underline'] == true;
    final strikethrough = map['strikethrough'] == true;
    final fitContent = map['fitContent'] == true;
    final glass = map['glass'] == true;
    final glassStyle = map['glassStyle']?.toString();
    final fontFamily = map['fontFamily']?.toString();
    final borderRadius = (map['borderRadius'] as num?)?.toDouble();
    final width = (map['width'] as num?)?.toDouble();
    final selfAlign = map['selfAlign']?.toString();
    final selfAlignVertical = map['selfAlignVertical']?.toString();

    return SlideBlock(
      id: blockId,
      type: type,
      content: resolvedContent,
      extra: extra,
      caption: caption,
      backgroundColor: backgroundColor,
      textColor: textColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
      padding: padding,
      marginVertical: marginVertical,
      fontSize: fontSize,
      horizontalAlign: horizontalAlign,
      verticalAlign: verticalAlign,
      minHeight: minHeight,
      bold: bold,
      italic: italic,
      underline: underline,
      strikethrough: strikethrough,
      fitContent: fitContent,
      glass: glass,
      glassStyle: glassStyle,
      fontFamily: fontFamily,
      borderRadius: borderRadius,
      width: width,
      selfAlign: selfAlign,
      selfAlignVertical: selfAlignVertical,
    );
  }

  /// Resolves block types from common string names and aliases
  static SlideBlockType _resolveBlockType(String raw) {
    switch (raw) {
      case 'heading':
      case 'h1':
      case 'title':
      case 'header':
        return SlideBlockType.heading;
      case 'subheading':
      case 'h2':
      case 'subtitle':
        return SlideBlockType.subheading;
      case 'code':
      case 'snippet':
      case 'program':
        return SlideBlockType.code;
      case 'bulletlist':
      case 'bullets':
      case 'list':
      case 'bullet_list':
        return SlideBlockType.bulletList;
      case 'callout':
      case 'note':
      case 'tip':
      case 'warning':
      case 'info':
      case 'alert':
        return SlideBlockType.callout;
      case 'imageurl':
      case 'image':
      case 'img':
      case 'picture':
      case 'photo':
        return SlideBlockType.imageUrl;
      case 'math':
      case 'latex':
      case 'formula':
      case 'equation':
        return SlideBlockType.math;
      case 'svg':
      case 'svg_code':
      case 'diagram':
      case 'vector':
      case 'tree':
        return SlideBlockType.svg;
      case 'table':
      case 'grid':
      case 'datatable':
        return SlideBlockType.table;
      case 'video':
      case 'youtube':
      case 'embed':
        return SlideBlockType.video;
      case 'card':
      case 'cards':
      case 'cardbox':
      case 'framedbox':
      case 'panel':
        return SlideBlockType.card;
      case 'columns':
      case 'column':
      case 'grid_columns':
      case 'multicolumn':
      case 'row':
        return SlideBlockType.columns;
      case 'banner':
      case 'section_banner':
      case 'divider_banner':
        return SlideBlockType.banner;
      case 'text':
      case 'styledtext':
      case 'freetext':
      case 'richtext':
        return SlideBlockType.text;
      case 'container':
      case 'box':
      case 'frame':
      case 'group':
        return SlideBlockType.container;
      case 'paragraph':
      case 'body':
      default:
        return SlideBlockType.paragraph;
    }
  }

  /// Normalizes slide theme
  static String _normalizeTheme(String? rawTheme) {
    if (rawTheme == null || rawTheme.isEmpty) return 'darkGlass';
    const validThemes = [
      'darkGlass',
      'jyamitiCosmos',
      'midnightNeon',
      'emeraldSlate',
      'sunsetViolet',
      'cleanLight',
    ];
    for (final t in validThemes) {
      if (t.toLowerCase() == rawTheme.toLowerCase()) return t;
    }
    return 'darkGlass';
  }

  /// Parses slide quiz
  static SlideQuiz? _parseQuiz(Map<String, dynamic> map) {
    final question = map['question']?.toString() ?? '';
    if (question.isEmpty) return null;

    List<String> options = [];
    if (map['options'] is List) {
      options = (map['options'] as List<dynamic>)
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    if (options.length < 2) {
      options = ['Option A', 'Option B', 'Option C', 'Option D'];
    }

    final correctIndex = (map['correctIndex'] as num?)?.toInt() ?? 0;
    final explanation = map['explanation']?.toString() ?? '';

    return SlideQuiz(
      question: question,
      options: options,
      correctIndex: correctIndex.clamp(0, options.length - 1),
      explanation: explanation,
    );
  }

  /// Exports a single slide to a formatted JSON string
  static String exportSlideJson(SlideItem slide) {
    return _prettyEncoder.convert(slide.toMap());
  }

  /// Exports a list of slides to a formatted JSON string
  static String exportSlideListJson(List<SlideItem> slides) {
    return _prettyEncoder.convert(slides.map((s) => s.toMap()).toList());
  }

  /// Exports an entire slide deck to a formatted JSON string
  static String exportDeckJson(SlideDeck deck) {
    return _prettyEncoder.convert(deck.toMap());
  }

  /// Beautifies any JSON string
  static String beautifyJson(String raw) {
    try {
      final decoded = json.decode(raw);
      return _prettyEncoder.convert(decoded);
    } catch (_) {
      return raw;
    }
  }

  // --- Sample Templates for UI Reference & Quick Load ---
  //
  // Exactly 3 categories (single slide / multi-slide array / full course
  // deck) -- each one is a COMPLETE reference covering every block type
  // (heading, subheading, paragraph, code, bulletList, callout, imageUrl,
  // math, svg, table, video, card, columns, banner) and every slide-level
  // field (theme OR a backgroundType override, enableWhiteboard, quiz),
  // not just a couple of new additions each. `columns` (with genuinely
  // mixed nested content -- an image, a card, a table, not just text) and
  // `banner` specifically appear in ALL three, since those are the
  // features most likely to get missed otherwise.
  //
  // sampleSingleSlideJson has only one slide, so everything lives in it.
  // sampleMultiSlideJson/sampleFullDeckJson each have 2 slides and split
  // the 14 types 7/7 across them (same split both times) so any one
  // slide stays a realistic length rather than every slide trying to
  // hold all 14 at once -- the EXAMPLE as a whole is still exhaustive.
  // Each of the 3 examples also demonstrates a different backgroundType
  // (gradient / solidColor / image) so all three get covered somewhere
  // across the full set.

  static String get sampleSingleSlideJson => _prettyEncoder.convert({
    "title": "Pythagorean Theorem",
    "theme": "darkGlass",
    "enableWhiteboard": true,
    "backgroundType": "gradient",
    "backgroundColor": "FF2E1065",
    "backgroundColor2": "FF0F172A",
    "blocks": [
      {
        "type": "banner",
        "content": "Unit 3: Right Triangle Geometry",
        "backgroundColor": "FFF59E0B",
        "textColor": "FF000000",
        "borderColor": "FF78350F",
        "borderWidth": 2.0,
        "padding": 20.0,
        "marginVertical": 14.0,
        "fontSize": 24.0,
        "horizontalAlign": "center",
        "verticalAlign": "center",
        "minHeight": 90.0,
        "glass": true,
        "glassStyle": "subtle",
      },
      {"type": "heading", "content": "Fundamental Geometry"},
      {
        "type": "subheading",
        "content": "Right Triangles & The Hypotenuse",
        "textColor": "FFFBBF24",
      },
      {
        "type": "paragraph",
        "content":
            "In mathematics, the Pythagorean theorem is a fundamental relation in Euclidean geometry among the three sides of a right triangle -- written inline as \$a^2 + b^2 = c^2\$ for quick reference.",
      },
      {
        "type": "text",
        "content": "Highlight: the theorem only holds for RIGHT triangles.",
        "textColor": "FFFBBF24",
        "backgroundColor": "331E293B",
        "borderColor": "FFFBBF24",
        "borderWidth": 1.5,
        "fontSize": 17.0,
        "horizontalAlign": "center",
        "bold": true,
        "underline": true,
        "fitContent": true,
        "fontFamily": "Space Grotesk",
      },
      {
        "type": "math",
        "content": "a^2 + b^2 = c^2",
        "backgroundColor": "331E293B",
        "borderColor": "FF6366F1",
        "borderWidth": 1.5,
        "borderRadius": 20.0,
        "padding": 18.0,
        "width": 0.6,
        "selfAlign": "center",
      },
      {
        "type": "svg",
        "content":
            "<svg viewBox='0 0 400 200' xmlns='http://www.w3.org/2000/svg'>\n  <rect width='400' height='200' fill='#0b2240' rx='12'/>\n  <polygon points='60,160 300,160 60,40' fill='none' stroke='#6366f1' stroke-width='3'/>\n  <text x='200' y='105' fill='#ffffff' font-size='16' text-anchor='middle' font-weight='bold'>Right Triangle</text>\n</svg>",
        "extra": "boxed",
      },
      {
        "type": "code",
        "content":
            "import 'dart:math';\n\ndouble hypotenuse(double a, double b) {\n  return sqrt(a * a + b * b);\n}",
        "extra": "dart",
      },
      {
        "type": "bulletList",
        "content":
            "Applies only to right-angled triangles\nForms the basis of coordinate geometry\nDiscovered independently across many ancient cultures",
        "extra": "numbered",
        "textColor": "FFFBBF24",
        "borderColor": "FF34D399",
      },
      {
        "type": "callout",
        "content":
            "Remember: c represents the length of the hypotenuse opposite the right angle.",
        "extra": "tip",
      },
      {
        "type": "imageUrl",
        "content":
            "https://images.unsplash.com/photo-1635070041078-e363dbe005cb?w=800",
        "caption": "A right triangle with labeled sides",
      },
      {
        "type": "table",
        "headers": ["a", "b", "c (hypotenuse)"],
        "rows": [
          ["3", "4", "5"],
          ["5", "12", "13"],
          ["8", "15", "17"],
        ],
      },
      {
        "type": "video",
        "content": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "caption": "Watch: a visual proof of the theorem",
      },
      {
        "type": "card",
        "caption": "Practice Set",
        "content": "3-4-5\n5-12-13\n8-15-17",
        "extra": "boxed",
        "borderColor": "FF10B981",
        "horizontalAlign": "center",
        "glass": true,
      },
      {
        "type": "columns",
        "backgroundColor": "220F172A",
        "borderColor": "FF34D399",
        "borderWidth": 1.0,
        "borderRadius": 16.0,
        "padding": 12.0,
        "marginVertical": 8.0,
        "width": 0.95,
        "minHeight": 220.0,
        "horizontalAlign": "left",
        "verticalAlign": "top",
        "selfAlign": "center",
        "selfAlignVertical": "center",
        "columns": [
          [
            {"type": "heading", "content": "Diagram"},
            {
              "type": "imageUrl",
              "content":
                  "https://images.unsplash.com/photo-1635070041078-e363dbe005cb?w=600",
              "caption": "Right triangle, sides labeled",
            },
            {
              "type": "bulletList",
              "content": "Two legs\nOne hypotenuse\nOne right angle",
            },
            {
              "type": "text",
              "content": "Tip: label the right angle first.",
              "textColor": "FF34D399",
              "fontSize": 14.0,
              "italic": true,
            },
          ],
          [
            {"type": "heading", "content": "Formula"},
            {
              "type": "card",
              "caption": "Key Formula",
              "content": "a^2 + b^2 = c^2",
              "extra": "boxed",
              "borderColor": "FFF472B6",
            },
            {
              "type": "table",
              "headers": ["Term", "Meaning"],
              "rows": [
                ["a, b", "the two legs"],
                ["c", "the hypotenuse"],
              ],
            },
          ],
        ],
      },
      {
        "type": "container",
        "backgroundColor": "331E293B",
        "borderColor": "FFA78BFA",
        "borderWidth": 1.5,
        "borderRadius": 18.0,
        "padding": 16.0,
        "marginVertical": 10.0,
        "width": 0.9,
        "minHeight": 160.0,
        "horizontalAlign": "center",
        "verticalAlign": "center",
        "selfAlign": "center",
        "selfAlignVertical": "bottom",
        "children": [
          {"type": "subheading", "content": "Quick Recap"},
          {
            "type": "text",
            "content":
                "Everything above in one glance: a^2 + b^2 = c^2, always true for right triangles.",
            "italic": true,
          },
        ],
      },
    ],
    "quiz": {
      "question": "Which side of a right triangle is the hypotenuse?",
      "options": [
        "The side opposite the right angle",
        "The shortest side",
        "The adjacent vertical side",
        "None of the above",
      ],
      "correctIndex": 0,
      "explanation":
          "The hypotenuse is the longest side of a right-angled triangle, directly opposite the 90-degree angle.",
    },
  });

  static String get sampleMultiSlideJson => _prettyEncoder.convert([
    {
      "title": "Module 1: Coordinate Geometry",
      "theme": "midnightNeon",
      "blocks": [
        {
          "type": "banner",
          "content": "Module 1: Coordinate Geometry",
          "backgroundColor": "FF0EA5E9",
          "textColor": "FFFFFFFF",
          "borderColor": "FF075985",
          "borderWidth": 2.0,
          "padding": 18.0,
          "marginVertical": 12.0,
          "fontSize": 22.0,
          "horizontalAlign": "left",
          "verticalAlign": "center",
          "minHeight": 80.0,
          "glass": true,
          "glassStyle": "subtle",
        },
        {"type": "heading", "content": "Introduction to 2D Cartesian Plane"},
        {
          "type": "subheading",
          "content": "Distance Between Two Points",
          "textColor": "FF38BDF8",
        },
        {
          "type": "paragraph",
          "content":
              "Every point in the plane is represented by an ordered pair of real numbers (x, y).",
        },
        {
          "type": "text",
          "content":
              "Distance is always non-negative -- it's the magnitude of displacement.",
          "textColor": "FF38BDF8",
          "fontSize": 16.0,
          "horizontalAlign": "left",
          "italic": true,
          "fontFamily": "Outfit",
        },
        {
          "type": "math",
          "content": "d = \\sqrt{(x_2 - x_1)^2 + (y_2 - y_1)^2}",
          "backgroundColor": "331E293B",
          "borderColor": "FF0EA5E9",
          "borderWidth": 1.5,
          "borderRadius": 20.0,
          "padding": 18.0,
          "width": 0.6,
          "selfAlign": "center",
        },
        {
          "type": "svg",
          "content":
              "<svg viewBox='0 0 400 200' xmlns='http://www.w3.org/2000/svg'>\n  <rect width='400' height='200' fill='#0b2240' rx='12'/>\n  <circle cx='120' cy='140' r='6' fill='#38bdf8'/>\n  <circle cx='280' cy='60' r='6' fill='#38bdf8'/>\n  <line x1='120' y1='140' x2='280' y2='60' stroke='#818cf8' stroke-width='2'/>\n  <text x='200' y='185' fill='#ffffff' font-size='14' text-anchor='middle'>Distance between two points</text>\n</svg>",
          "extra": "boxed",
        },
        {
          "type": "columns",
          "backgroundColor": "220F172A",
          "borderColor": "FF0EA5E9",
          "borderWidth": 1.0,
          "borderRadius": 16.0,
          "padding": 12.0,
          "marginVertical": 8.0,
          "width": 0.95,
          "minHeight": 220.0,
          "horizontalAlign": "left",
          "verticalAlign": "top",
          "selfAlign": "center",
          "columns": [
            [
              {"type": "heading", "content": "Quadrants"},
              {
                "type": "bulletList",
                "content":
                    "Quadrant I: (+, +)\nQuadrant II: (-, +)\nQuadrant III: (-, -)\nQuadrant IV: (+, -)",
              },
            ],
            [
              {"type": "heading", "content": "Example Points"},
              {
                "type": "table",
                "headers": ["Point", "Quadrant"],
                "rows": [
                  ["(3, 2)", "I"],
                  ["(-4, 1)", "II"],
                ],
              },
              {
                "type": "text",
                "content": "Note the sign pattern above.",
                "textColor": "FFA78BFA",
                "fontSize": 14.0,
                "underline": true,
              },
            ],
          ],
        },
        {
          "type": "container",
          "backgroundColor": "331E1B4B",
          "borderColor": "FF818CF8",
          "borderWidth": 1.5,
          "borderRadius": 18.0,
          "padding": 16.0,
          "marginVertical": 10.0,
          "width": 0.9,
          "minHeight": 160.0,
          "horizontalAlign": "center",
          "verticalAlign": "center",
          "selfAlign": "center",
          "selfAlignVertical": "center",
          "children": [
            {"type": "subheading", "content": "Quick Recap"},
            {
              "type": "bulletList",
              "content":
                  "Distance is always positive\nQuadrants number counter-clockwise from top-right",
            },
          ],
        },
      ],
    },
    {
      "title": "Module 2: Slope and Intercept",
      "theme": "emeraldSlate",
      "backgroundType": "solidColor",
      "backgroundColor": "FF0F172A",
      "blocks": [
        {
          "type": "code",
          "content":
              "# Calculating slope in Python\ndef slope(p1, p2):\n    return (p2[1] - p1[1]) / (p2[0] - p1[0])",
          "extra": "python",
        },
        {
          "type": "bulletList",
          "content":
              "Positive slope rises left to right\nNegative slope falls left to right\nZero slope is a horizontal line",
          "extra": "numbered",
          "textColor": "FF34D399",
          "borderColor": "FF10B981",
        },
        {
          "type": "callout",
          "content":
              "If denominator is zero, the line is strictly vertical with undefined slope.",
          "extra": "warning",
        },
        {
          "type": "imageUrl",
          "content":
              "https://images.unsplash.com/photo-1635070041078-e363dbe005cb?w=800",
          "caption": "Lines of varying slope",
        },
        {
          "type": "table",
          "headers": ["Slope", "Line Behavior"],
          "rows": [
            ["m > 0", "Rises left to right"],
            ["m < 0", "Falls left to right"],
            ["m = 0", "Horizontal"],
          ],
        },
        {
          "type": "video",
          "content": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
          "caption": "Watch: slope-intercept form explained",
        },
        {
          "type": "card",
          "caption": "Practice Set",
          "content": "y = 2x + 3\ny = -x + 7\n2y = 4x - 6",
          "extra": "boxed",
          "borderColor": "FF10B981",
          "horizontalAlign": "right",
          "glass": true,
        },
      ],
      "quiz": {
        "question": "In y = mx + b, what does b represent?",
        "options": [
          "The y-intercept",
          "The slope",
          "The x-intercept",
          "The domain",
        ],
        "correctIndex": 0,
        "explanation": "b is the y-intercept -- the value of y when x = 0.",
      },
    },
  ]);

  static String get sampleFullDeckJson => _prettyEncoder.convert({
    "title": "Quantum Mechanics & Wave Functions",
    "description":
        "Comprehensive introduction to Schrödinger's equation and state vectors.",
    "courseName": "Advanced Physics",
    "slides": [
      {
        "title": "Wave-Particle Duality",
        "theme": "sunsetViolet",
        "blocks": [
          {
            "type": "banner",
            "content": "Chapter 4: Wave-Particle Duality",
            "backgroundColor": "FFA78BFA",
            "textColor": "FF000000",
            "borderColor": "FF4C1D95",
            "borderWidth": 2.0,
            "padding": 18.0,
            "marginVertical": 12.0,
            "fontSize": 22.0,
            "horizontalAlign": "center",
            "verticalAlign": "center",
            "minHeight": 100.0,
            "glass": true,
            "glassStyle": "subtle",
          },
          {"type": "heading", "content": "The de Broglie Hypothesis"},
          {
            "type": "subheading",
            "content": "Matter Waves",
            "textColor": "FFA78BFA",
          },
          {
            "type": "paragraph",
            "content":
                "Matter exhibits wave-like properties with a wavelength inversely proportional to momentum.",
          },
          {
            "type": "text",
            "content": "Historical note (superseded by later experiments).",
            "textColor": "FFF87171",
            "fontSize": 15.0,
            "horizontalAlign": "right",
            "italic": true,
            "strikethrough": true,
            "fontFamily": "Merriweather",
          },
          {
            "type": "math",
            "content": "\\lambda = \\frac{h}{p}",
            "backgroundColor": "331E293B",
            "borderColor": "FFA78BFA",
            "borderWidth": 1.5,
            "borderRadius": 20.0,
            "padding": 18.0,
            "width": 0.6,
            "selfAlign": "center",
          },
          {
            "type": "svg",
            "content":
                "<svg viewBox='0 0 400 200' xmlns='http://www.w3.org/2000/svg'>\n  <rect width='400' height='200' fill='#1e1b4b' rx='12'/>\n  <path d='M20 100 Q 70 40, 120 100 T 220 100 T 320 100 T 420 100' stroke='#a78bfa' stroke-width='3' fill='none'/>\n  <text x='200' y='170' fill='#ffffff' font-size='14' text-anchor='middle'>A matter wave</text>\n</svg>",
            "extra": "boxed",
          },
          {
            "type": "columns",
            "backgroundColor": "220F172A",
            "borderColor": "FFA78BFA",
            "borderWidth": 1.0,
            "borderRadius": 16.0,
            "padding": 12.0,
            "marginVertical": 8.0,
            "width": 0.95,
            "minHeight": 220.0,
            "horizontalAlign": "left",
            "verticalAlign": "top",
            "selfAlign": "center",
            "selfAlignVertical": "bottom",
            "columns": [
              [
                {"type": "heading", "content": "Wave Model"},
                {
                  "type": "imageUrl",
                  "content":
                      "https://images.unsplash.com/photo-1635070041078-e363dbe005cb?w=600",
                  "caption": "Interference pattern",
                },
                {
                  "type": "bulletList",
                  "content":
                      "Exhibits interference\nExhibits diffraction\nDescribed by a wavelength",
                },
                {
                  "type": "text",
                  "content": "Confirmed by the double-slit experiment.",
                  "textColor": "FFA78BFA",
                  "fontSize": 14.0,
                  "italic": true,
                },
              ],
              [
                {"type": "heading", "content": "Particle Model"},
                {
                  "type": "card",
                  "caption": "Momentum",
                  "content": "p = mv",
                  "extra": "boxed",
                  "borderColor": "FF38BDF8",
                },
                {
                  "type": "table",
                  "headers": ["Property", "Value"],
                  "rows": [
                    ["Mass", "Defined"],
                    ["Position", "Localized"],
                  ],
                },
              ],
            ],
          },
          {
            "type": "container",
            "backgroundColor": "331E1B4B",
            "borderColor": "FFA78BFA",
            "borderWidth": 1.5,
            "borderRadius": 18.0,
            "padding": 16.0,
            "marginVertical": 10.0,
            "width": 0.85,
            "minHeight": 140.0,
            "horizontalAlign": "center",
            "verticalAlign": "center",
            "selfAlign": "center",
            "selfAlignVertical": "top",
            "children": [
              {"type": "subheading", "content": "Both Models, Side by Side"},
              {
                "type": "columns",
                "columns": [
                  [
                    {"type": "text", "content": "Wave: spread out, interferes"},
                  ],
                  [
                    {
                      "type": "text",
                      "content": "Particle: localized, has momentum",
                    },
                  ],
                ],
              },
            ],
          },
        ],
      },
      {
        "title": "Time-Dependent Schrödinger Equation",
        "theme": "darkGlass",
        "backgroundType": "image",
        "backgroundImageUrl":
            "https://images.unsplash.com/photo-1635070041078-e363dbe005cb?w=1200",
        "blocks": [
          {
            "type": "code",
            "content":
                "# Normalizing a wavefunction (schematic)\ndef normalize(psi, dx):\n    norm = sum(abs(p) ** 2 for p in psi) * dx\n    return [p / norm ** 0.5 for p in psi]",
            "extra": "python",
          },
          {
            "type": "bulletList",
            "content":
                "Governs how a quantum state evolves in time\nLinear and deterministic\nConserves total probability",
            "extra": "numbered",
            "textColor": "FFA78BFA",
            "borderColor": "FF818CF8",
          },
          {
            "type": "callout",
            "content": "\\hbar (h-bar) is Planck's constant divided by 2π.",
            "extra": "info",
          },
          {
            "type": "imageUrl",
            "content":
                "https://images.unsplash.com/photo-1635070041078-e363dbe005cb?w=800",
            "caption": "A wavefunction's probability density",
          },
          {
            "type": "table",
            "headers": ["Symbol", "Meaning"],
            "rows": [
              ["\\Psi", "Wavefunction"],
              ["\\hat{H}", "Hamiltonian operator"],
            ],
          },
          {
            "type": "video",
            "content": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "caption": "Watch: deriving the Schrödinger equation",
          },
          {
            "type": "card",
            "caption": "Core Formulation",
            "content":
                "i\\hbar \\frac{\\partial}{\\partial t} \\Psi = \\hat{H}\\Psi",
            "extra": "boxed",
            "borderColor": "FFA78BFA",
            "horizontalAlign": "center",
            "glass": true,
          },
        ],
        "quiz": {
          "question": "What does \\hbar represent in quantum equations?",
          "options": [
            "Reduced Planck constant (h / 2π)",
            "Boltzmann constant",
            "Speed of light in vacuum",
            "Permittivity of free space",
          ],
          "correctIndex": 0,
          "explanation":
              "\\hbar (h-bar) equals Planck's constant h divided by 2π.",
        },
      },
    ],
  });

  /// A ready-to-copy prompt for an external AI chat tool (ChatGPT, Claude,
  /// etc.) that converts an existing presentation (PPTX or otherwise) into
  /// this app's slide JSON format -- the "Copy Conversion Prompt" button
  /// next to "Load Sample" in SlideJsonImportDialog copies this to the
  /// clipboard so a tutor can paste it alongside their PPTX content into
  /// an AI tool, then paste the JSON result it produces back into the
  /// Paste JSON tab here. Deliberately just a big block of instructional
  /// text, not app JSON itself -- kept in this file (rather than inline
  /// in the dialog widget) purely to keep that widget file from being
  /// dominated by a multi-thousand-character string literal, the same
  /// reasoning as the sample*Json getters above.
  static String get pptxConversionPrompt => r'''
You are converting a PowerPoint presentation into a specific JSON format used by a math-tutoring app's slide CMS. Output ONLY valid JSON — no markdown code fences, no commentary before or after, no trailing commas.

=== OUTPUT SHAPE ===
Return a JSON ARRAY, one object per PPTX slide, in slide order:

[
  { "title": "...", "theme": "...", "blocks": [ ...block objects... ] },
  { "title": "...", "theme": "...", "blocks": [ ...block objects... ] }
]

Each slide object:
- "title" (string, required) — a short slide title, even if the PPTX slide has no explicit title text (summarize it).
- "theme" (string, optional) — one of: darkGlass, jyamitiCosmos, midnightNeon, emeraldSlate, sunsetViolet, cleanLight. Pick one that suits the content; jyamitiCosmos is a safe default.
- "blocks" (array, required) — the slide's content, as block objects (see below), in visual top-to-bottom order.

=== BLOCK OBJECT SHAPE ===
Every block is: { "type": "...", "content": "...", ...optional fields }

"type" must be one of these 16 values, and "content" means something different per type:

| type          | what "content" holds                                                              | notes |
|---------------|-------------------------------------------------------------------------------------|-------|
| heading       | main heading text                                                                   | use for the slide's H1-level title text |
| subheading    | secondary heading text                                                              | |
| paragraph     | a plain paragraph of text                                                           | |
| text          | short styled text (a label/note), supports bold/italic/underline (see below)        | use for short callout-style text, not paragraphs |
| bulletList    | list items joined with "\n" (one item per line)                                     | set "extra": "bullet" or "numbered" (default bullet) |
| callout       | a highlighted note/tip/warning box                                                  | set "extra": "info" | "tip" | "warning" |
| code          | source code text                                                                    | set "extra" to the language, e.g. "python" |
| math          | a math expression/equation as plain text, e.g. "a^2 + b^2 = c^2"                    | LaTeX-ish is fine, plain text preferred for simple equations |
| imageUrl      | a fully-qualified image URL                                                         | see IMAGES note below — do NOT invent fake URLs |
| svg           | raw inline `<svg>...</svg>` markup                                                  | only if you're generating an actual diagram |
| table         | leave "content" as "" and instead add top-level "headers": [...], "rows": [[...],...] | see TABLE example below |
| video         | leave "content" as "" and add "videoUrl": "..." instead                             | only if a real video URL is known |
| card          | body text; "caption" is the card's title                                            | a distinct highlighted box, e.g. for a key formula |
| columns       | leave "content" as "" and add "columns": [[block,...], [block,...]]                 | array of columns, each a list of nested block objects (side-by-side layout) |
| container     | leave "content" as "" and add "children": [block, block, ...]                       | a flat list of nested block objects, wrapped in one decorated box |
| banner        | a highlighted title/callout banner spanning the slide width                         | good for a module/section-opener slide |

Optional per-block styling fields (add only when it genuinely helps, otherwise omit — omitted means "use default"):
- "caption" (string) — used by card (title) and imageUrl (image caption).
- "textColor", "backgroundColor", "borderColor" — hex strings WITHOUT '#', e.g. "6366F1" (6-digit) or "FF6366F1" (8-digit with alpha).
- "borderWidth", "borderRadius", "padding", "marginVertical", "fontSize", "minHeight", "width" — numbers. "width" is a 0.0–1.0 fraction of slide width (only set if you want a narrower box).
- "horizontalAlign" / "verticalAlign" — "left"|"center"|"right" / "top"|"center"|"bottom" (positions content WITHIN a box).
- "selfAlign" — "left"|"center"|"right" (positions the box itself, only meaningful if "width" < 1.0).
- "bold" / "italic" / "underline" / "strikethrough" — booleans, mainly for "text" blocks.

=== TABLE EXAMPLE ===
{ "type": "table", "headers": ["Term", "Meaning"], "rows": [["Even number", "Divisible by 2"], ["Odd number", "Not divisible by 2"]] }

=== CONTAINER EXAMPLE (a boxed recap, narrower than full width, centered on the slide) ===
{
  "type": "container",
  "backgroundColor": "331E293B", "borderColor": "FFA78BFA", "borderRadius": 18, "padding": 16,
  "width": 0.8, "selfAlign": "center",
  "horizontalAlign": "center", "verticalAlign": "center", "minHeight": 160,
  "selfAlignVertical": "center",
  "children": [
    { "type": "subheading", "content": "Quick Recap" },
    { "type": "bulletList", "content": "Point one\nPoint two", "extra": "bullet" }
  ]
}

=== VISUAL FIDELITY — MATCH THE ORIGINAL SLIDE EXACTLY ===
Don't just capture the "idea" of a slide — reproduce it as faithfully as possible: same visual elements, same layout/positions, same labels and numbers, same colors where identifiable, same emphasis (bold/highlighted parts), in the same order they appear on the original slide. Do not simplify, paraphrase, or drop visual details to make conversion easier. If the original slide had 3 labeled arrows pointing at 3 parts of a number line, the SVG must have all 3 arrows at the correct positions with the correct labels — not "an arrow" as a stand-in.

=== DIAGRAMS: REDRAW AS SVG, DITTO SAME AS THE ORIGINAL ===
Any diagram, chart, number line, geometric figure, or drawn illustration on a slide must be redrawn as inline SVG that looks AS CLOSE AS POSSIBLE to the original — not a rough approximation. Match:
- The exact layout/positions of every element (don't rearrange or center things that were off-center in the original).
- Every label, number, and piece of text shown on the diagram, in the same position relative to the shapes.
- The number of shapes/points/arrows/segments — if the original shows 7 tick marks, draw 7 tick marks, not "a few."
- Relative proportions and spacing (a number line spanning -10 to 10 should have evenly spaced, correctly proportioned ticks, not a stylized guess).
- Colors, where the original used color meaningfully (e.g. red for negative, green for positive) — reproduce that color coding.

Example (number line from -5 to 5, matching this exact structure):
{
  "type": "svg",
  "content": "<svg viewBox='0 0 500 120' xmlns='http://www.w3.org/2000/svg'><rect width='500' height='120' fill='#0b2240' rx='12'/><line x1='40' y1='60' x2='460' y2='60' stroke='#818cf8' stroke-width='3'/><circle cx='250' cy='60' r='6' fill='#38bdf8'/><text x='250' y='40' fill='#ffffff' font-size='16' text-anchor='middle'>0</text><text x='40' y='40' fill='#ffffff' font-size='16' text-anchor='middle'>-5</text><text x='460' y='40' fill='#ffffff' font-size='16' text-anchor='middle'>5</text></svg>",
  "extra": "boxed"
}

Technical rules (unchanged): viewBox roughly 400-600 wide x 150-300 tall, self-contained (no external fonts/images/CSS classes), dark background rect with light strokes/text to match the dark slide theme, "extra": "boxed" to render with a border.

Take the time to actually count and place every element correctly — a diagram that's "close enough" but missing labels or mispositioned elements is not acceptable; it should be recognizably the SAME diagram, not a redrawn approximation of it.

ONLY fall back to a placeholder callout (below) when it's a genuine photograph/screenshot with no line-art structure to trace at all — every drawn diagram, chart, or geometric figure should be redrawn in full, matching detail.

=== PHOTOS/SCREENSHOTS (truly can't be redrawn) ===
For an actual photo or screenshot with no vector structure, and no real hosted URL exists, skip the imageUrl block and add a placeholder callout instead:
{ "type": "callout", "content": "[Image placeholder: description of what was here]", "extra": "info" }
Never invent a fake image URL — it will render as a broken image.


=== FULL WORKED EXAMPLE ===
[
  {
    "title": "What is Place Value?",
    "theme": "jyamitiCosmos",
    "blocks": [
      { "type": "heading", "content": "What is Place Value?" },
      { "type": "paragraph", "content": "Every digit in a number has a place value based on its position." },
      {
        "type": "table",
        "headers": ["Number", "Thousands", "Hundreds", "Tens", "Ones"],
        "rows": [["3,482", "3", "4", "8", "2"]]
      },
      {
        "type": "callout",
        "content": "The same digit can have a different value depending on where it sits in the number.",
        "extra": "tip"
      }
    ]
  },
  {
    "title": "Even and Odd Numbers",
    "theme": "jyamitiCosmos",
    "blocks": [
      { "type": "heading", "content": "Even and Odd Numbers" },
      {
        "type": "bulletList",
        "content": "Even numbers end in 0, 2, 4, 6, or 8\nOdd numbers end in 1, 3, 5, 7, or 9\nZero is an even number",
        "extra": "bullet"
      },
      { "type": "math", "content": "12 = 2 x 6  (even)" },
      {
        "type": "container",
        "backgroundColor": "331E293B", "borderColor": "FFA78BFA", "borderRadius": 18, "padding": 16,
        "children": [
          { "type": "subheading", "content": "Quick Recap" },
          { "type": "bulletList", "content": "Look at the last digit\nEven -> 0,2,4,6,8\nOdd -> 1,3,5,7,9" }
        ]
      }
    ]
  }
]

=== NOW CONVERT ===
Convert the following PowerPoint content (attached / pasted below) into this exact JSON array format, following every rule above. Output ONLY the JSON array, nothing else.
''';
}
