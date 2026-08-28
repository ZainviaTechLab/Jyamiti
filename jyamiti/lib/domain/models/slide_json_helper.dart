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
  static SlideItem _parseSingleSlide(Map<String, dynamic> map, int fallbackIndex) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final slideId = map['id']?.toString().isNotEmpty == true
        ? map['id'].toString()
        : 'slide_${now}_$fallbackIndex';

    final title = map['title']?.toString() ??
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
      final fallbackContent = map['content']?.toString() ?? map['body']?.toString();
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
      (e) => e.name.toLowerCase() ==
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
      contentVerticalAlign: map['contentVerticalAlign']?.toString() ?? 'top',
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

    final rawType = (map['type'] ?? 'paragraph').toString().toLowerCase().trim();
    final content = map['content']?.toString() ??
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
      resolvedContent = map['videoUrl']?.toString() ??
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
      case 'box':
      case 'cardbox':
      case 'framedbox':
      case 'container':
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
      case 'paragraph':
      case 'text':
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

  static String get sampleSingleSlideJson => _prettyEncoder.convert({
        "title": "Pythagorean Theorem",
        "theme": "darkGlass",
        "enableWhiteboard": true,
        "blocks": [
          {
            "type": "heading",
            "content": "Fundamental Geometry"
          },
          {
            "type": "paragraph",
            "content": "In mathematics, the Pythagorean theorem is a fundamental relation in Euclidean geometry among the three sides of a right triangle."
          },
          {
            "type": "math",
            "content": "a^2 + b^2 = c^2"
          },
          {
            "type": "table",
            "headers": ["a", "b", "c (hypotenuse)"],
            "rows": [
              ["3", "4", "5"],
              ["5", "12", "13"],
              ["8", "15", "17"]
            ]
          },
          {
            "type": "callout",
            "content": "Remember: c represents the length of the hypotenuse opposite the right angle.",
            "extra": "tip",
            "backgroundColor": "331E1B4B",
            "borderColor": "FF818CF8",
            "borderWidth": 2.0
          }
        ],
        "quiz": {
          "question": "Which side of a right triangle is the hypotenuse?",
          "options": [
            "The side opposite the right angle",
            "The shortest side",
            "The adjacent vertical side",
            "None of the above"
          ],
          "correctIndex": 0,
          "explanation": "The hypotenuse is the longest side of a right-angled triangle, directly opposite the 90-degree angle."
        }
      });

  static String get sampleMultiSlideJson => _prettyEncoder.convert([
        {
          "title": "Module 1: Coordinate Geometry",
          "theme": "midnightNeon",
          "blocks": [
            {
              "type": "heading",
              "content": "Introduction to 2D Cartesian Plane"
            },
            {
              "type": "paragraph",
              "content": "Every point in the plane is represented by an ordered pair of real numbers (x, y)."
            },
            {
              "type": "math",
              "content": "d = \\sqrt{(x_2 - x_1)^2 + (y_2 - y_1)^2}"
            },
            {
              "type": "video",
              "content": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
              "caption": "Watch: the distance formula, visually explained"
            }
          ]
        },
        {
          "title": "Module 2: Slope and Intercept",
          "theme": "emeraldSlate",
          "blocks": [
            {
              "type": "heading",
              "content": "Equation of a Line"
            },
            {
              "type": "code",
              "content": "# Calculating slope in Python\ndef slope(p1, p2):\n    return (p2[1] - p1[1]) / (p2[0] - p1[0])",
              "extra": "python"
            },
            {
              "type": "callout",
              "content": "If denominator is zero, the line is strictly vertical with undefined slope.",
              "extra": "warning"
            },
            {
              "type": "card",
              "caption": "Practice Set",
              "content": "y = 2x + 3\ny = -x + 7\n2y = 4x - 6",
              "extra": "boxed",
              "borderColor": "FF10B981"
            }
          ]
        }
      ]);

  static String get sampleFullDeckJson => _prettyEncoder.convert({
        "title": "Quantum Mechanics & Wave Functions",
        "description": "Comprehensive introduction to Schrödinger's equation and state vectors.",
        "courseName": "Advanced Physics",
        "slides": [
          {
            "title": "Wave-Particle Duality",
            "theme": "sunsetViolet",
            "blocks": [
              {
                "type": "heading",
                "content": "The de Broglie Hypothesis"
              },
              {
                "type": "paragraph",
                "content": "Matter exhibits wave-like properties with a wavelength inversely proportional to momentum."
              },
              {
                "type": "math",
                "content": "\\lambda = \\frac{h}{p}"
              }
            ]
          },
          {
            "title": "Time-Dependent Schrödinger Equation",
            "theme": "darkGlass",
            "backgroundType": "gradient",
            "backgroundColor": "FF2E1065",
            "backgroundColor2": "FF0F172A",
            "blocks": [
              {
                "type": "heading",
                "content": "Core Formulation"
              },
              {
                "type": "math",
                "content": "i\\hbar \\frac{\\partial}{\\partial t} \\Psi(\\mathbf{r},t) = \\hat{H}\\Psi(\\mathbf{r},t)"
              }
            ],
            "quiz": {
              "question": "What does \\hbar represent in quantum equations?",
              "options": [
                "Reduced Planck constant (h / 2π)",
                "Boltzmann constant",
                "Speed of light in vacuum",
                "Permittivity of free space"
              ],
              "correctIndex": 0,
              "explanation": "\\hbar (h-bar) equals Planck's constant h divided by 2π."
            }
          }
        ]
      });

  /// Dedicated example for the newest/most involved features: a
  /// `columns` block with genuinely mixed content per column (not just
  /// plain text -- an image, a table, a card, a formula, a bullet list,
  /// spread across two columns), plus a slide-level image background and
  /// per-block background/text/outline styling on top of it.
  static String get sampleColumnsLayoutJson => _prettyEncoder.convert({
        "title": "Linear vs Quadratic Functions",
        "theme": "darkGlass",
        "backgroundType": "image",
        "backgroundImageUrl":
            "https://images.unsplash.com/photo-1635070041078-e363dbe005cb?w=1200",
        "blocks": [
          {
            "type": "heading",
            "content": "Side-by-Side Comparison",
            "backgroundColor": "CC0F172A",
            "textColor": "FFFFFFFF"
          },
          {
            "type": "columns",
            "columns": [
              [
                {
                  "type": "heading",
                  "content": "Linear Function",
                  "textColor": "FF38BDF8"
                },
                {
                  "type": "imageUrl",
                  "content":
                      "https://images.unsplash.com/photo-1635070041078-e363dbe005cb?w=600",
                  "caption": "A straight-line graph"
                },
                {
                  "type": "math",
                  "content": "y = mx + b"
                },
                {
                  "type": "bulletList",
                  "content":
                      "Constant rate of change\nGraph is a straight line\nDegree 1 polynomial"
                }
              ],
              [
                {
                  "type": "heading",
                  "content": "Quadratic Function",
                  "textColor": "FFF472B6"
                },
                {
                  "type": "card",
                  "caption": "Standard Form",
                  "content": "y = ax^2 + bx + c",
                  "extra": "boxed",
                  "borderColor": "FFF472B6"
                },
                {
                  "type": "table",
                  "headers": ["a", "Shape"],
                  "rows": [
                    ["> 0", "Opens upward"],
                    ["< 0", "Opens downward"]
                  ]
                },
                {
                  "type": "bulletList",
                  "content":
                      "Variable rate of change\nGraph is a parabola\nDegree 2 polynomial"
                }
              ]
            ]
          }
        ]
      });
}
