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

    return SlideItem(
      id: slideId,
      slideIndex: fallbackIndex,
      title: title,
      blocks: blocks,
      theme: theme,
      quiz: quiz,
      enableWhiteboard: enableWhiteboard,
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

    final extra = map['extra']?.toString() ?? map['language']?.toString();
    final caption = map['caption']?.toString();

    return SlideBlock(
      id: blockId,
      type: type,
      content: content,
      extra: extra,
      caption: caption,
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
            "type": "callout",
            "content": "Remember: c represents the length of the hypotenuse opposite the right angle.",
            "extra": "tip"
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
}
