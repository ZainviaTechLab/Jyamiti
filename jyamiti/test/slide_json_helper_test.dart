import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jyamiti/domain/models/slide_deck_models.dart';
import 'package:jyamiti/domain/models/slide_json_helper.dart';
import 'package:jyamiti/presentation/features/slides/widgets/svg_style_inliner.dart';

void main() {
  group('SlideJsonHelper Tests', () {
    test('parses single slide JSON correctly', () {
      final json = SlideJsonHelper.sampleSingleSlideJson;
      final result = SlideJsonHelper.parseJson(json);

      expect(result.isSuccess, isTrue);
      expect(result.slides.length, 1);
      final slide = result.slides.first;
      expect(slide.title, 'Pythagorean Theorem');
      expect(slide.theme, 'darkGlass');
      expect(slide.blocks.length, 5);
      expect(slide.blocks[0].type, SlideBlockType.heading);
      expect(slide.blocks[1].type, SlideBlockType.paragraph);
      expect(slide.blocks[2].type, SlideBlockType.math);
      expect(slide.blocks[3].type, SlideBlockType.table);
      expect(slide.blocks[4].type, SlideBlockType.callout);
      expect(slide.blocks[4].backgroundColor, '331E1B4B');
      expect(slide.blocks[4].borderColor, 'FF818CF8');
      expect(slide.quiz, isNotNull);
      expect(slide.quiz!.question, 'Which side of a right triangle is the hypotenuse?');
      expect(slide.quiz!.correctIndex, 0);
    });

    test('parses multi-slide JSON array correctly', () {
      final json = SlideJsonHelper.sampleMultiSlideJson;
      final result = SlideJsonHelper.parseJson(json);

      expect(result.isSuccess, isTrue);
      expect(result.slides.length, 2);
      expect(result.slides[0].title, 'Module 1: Coordinate Geometry');
      expect(result.slides[0].theme, 'midnightNeon');
      expect(result.slides[1].title, 'Module 2: Slope and Intercept');
      expect(result.slides[1].theme, 'emeraldSlate');
    });

    test('parses full course slide deck JSON correctly', () {
      final json = SlideJsonHelper.sampleFullDeckJson;
      final result = SlideJsonHelper.parseJson(json);

      expect(result.isSuccess, isTrue);
      expect(result.deckTitle, 'Quantum Mechanics & Wave Functions');
      expect(result.courseName, 'Advanced Physics');
      expect(result.slides.length, 2);
      expect(result.slides[0].title, 'Wave-Particle Duality');
      expect(result.slides[1].title, 'Time-Dependent Schrödinger Equation');
    });

    test('handles alias mapping for block types gracefully', () {
      final customJson = '''
      {
        "title": "Alias Test",
        "blocks": [
          {"type": "h1", "content": "Header"},
          {"type": "formula", "content": "E = mc^2"},
          {"type": "bullets", "content": "A\\nB\\nC"},
          {"type": "snippet", "content": "print('hello')", "language": "python"},
          {"type": "warning", "content": "Be careful"}
        ]
      }
      ''';

      final result = SlideJsonHelper.parseJson(customJson);
      expect(result.isSuccess, isTrue);
      final blocks = result.slides.first.blocks;
      expect(blocks[0].type, SlideBlockType.heading);
      expect(blocks[1].type, SlideBlockType.math);
      expect(blocks[2].type, SlideBlockType.bulletList);
      expect(blocks[3].type, SlideBlockType.code);
      expect(blocks[3].extra, 'python');
      expect(blocks[4].type, SlideBlockType.callout);
    });

    test('returns failure on malformed JSON', () {
      final malformed = '{ title: "invalid", blocks: [ }';
      final result = SlideJsonHelper.parseJson(malformed);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Invalid JSON syntax'));
    });

    test('exports slide and full deck to valid JSON', () {
      final deck = SlideDeck(
        id: 'd1',
        courseId: 'c1',
        courseName: 'Math',
        title: 'Trigonometry',
        description: 'Basics',
        slides: [
          SlideItem(
            id: 's1',
            slideIndex: 0,
            title: 'Sine and Cosine',
            blocks: [
              SlideBlock(id: 'b1', type: SlideBlockType.heading, content: 'Trig Functions'),
            ],
          )
        ],
        createdAt: DateTime.now(),
      );

      final exportedDeck = SlideJsonHelper.exportDeckJson(deck);
      final parseDeckResult = SlideJsonHelper.parseJson(exportedDeck);
      expect(parseDeckResult.isSuccess, isTrue);
      expect(parseDeckResult.deckTitle, 'Trigonometry');
      expect(parseDeckResult.slides.length, 1);

      final exportedSlide = SlideJsonHelper.exportSlideJson(deck.slides.first);
      final parseSlideResult = SlideJsonHelper.parseJson(exportedSlide);
      expect(parseSlideResult.isSuccess, isTrue);
      expect(parseSlideResult.slides.length, 1);
      expect(parseSlideResult.slides.first.title, 'Sine and Cosine');
    });

    test('parses LLM SVG branch diagram and LaTeX paragraph slide correctly', () {
      const llmJson = '''
      {
        "title": "A systematic way to list all eight expressions",
        "courseName": "Mathematics",
        "theme": "darkGlass",
        "slides": [
          {
            "slideIndex": 0,
            "title": "A systematic way to list all eight expressions",
            "blocks": [
              {
                "type": "svg",
                "content": "<svg viewBox='0 0 800 450' xmlns='http://www.w3.org/2000/svg'><text x='100' y='218'>3</text></svg>"
              },
              {
                "type": "paragraph",
                "content": "Eight such expressions are possible — \$\$2 \\\\times 2 \\\\times 2 = 8\$\$ sign choices."
              }
            ]
          }
        ]
      }
      ''';

      final result = SlideJsonHelper.parseJson(llmJson);
      expect(result.isSuccess, isTrue);
      expect(result.deckTitle, 'A systematic way to list all eight expressions');
      expect(result.courseName, 'Mathematics');
      expect(result.slides.length, 1);

      final slide = result.slides.first;
      expect(slide.blocks.length, 2);
      expect(slide.blocks[0].type, SlideBlockType.svg);
      expect(slide.blocks[0].content, contains('<svg'));
      expect(slide.blocks[1].type, SlideBlockType.paragraph);
      expect(slide.blocks[1].content, contains(r'$$2 \times 2 \times 2 = 8$$'));
    });

    test('SvgStyleInliner inlines CSS classes and strips style tags', () {
      const rawSvg =
          "<svg viewBox='0 0 800 450' xmlns='http://www.w3.org/2000/svg' style='background-color:#0b2240;'> <style> text { fill: #ffffff; font-weight: bold; } .line { stroke: #ffffff; stroke-width: 2; } .dashed { stroke: #6b82a6; stroke-width: 1.5; stroke-dasharray: 4 4; } </style> <line x1='115' y1='210' x2='210' y2='155' class='line' /> <line x1='545' y1='48' x2='640' y2='48' class='dashed' /> <text x='100' y='218' class='number'>3</text> </svg>";

      final processed = SvgStyleInliner.process(rawSvg);

      // Style block must be stripped to prevent flutter_svg unhandled element warnings
      expect(processed.contains('<style'), isFalse);
      // Background rect must be injected with rounded corners
      expect(processed.contains("<rect width='100%' height='100%' fill='#0b2240' rx='16' ry='16' />"), isTrue);
      // .line class must receive stroke and stroke-width attributes
      expect(processed.contains("stroke='#ffffff'"), isTrue);
      expect(processed.contains("stroke-width='2'"), isTrue);
      // .dashed class must receive stroke-dasharray attribute
      expect(processed.contains("stroke-dasharray='4 4'"), isTrue);
      // text tag must receive fill and font-weight
      expect(processed.contains("font-weight='bold'"), isTrue);
    });

    test('parses and handles native card blocks with custom border and content', () {
      const cardJson = '''
      {
        "title": "Consecutive Numbers",
        "slides": [
          {
            "slideIndex": 0,
            "title": "Exploring Sums",
            "blocks": [
              {
                "type": "card",
                "caption": "Set 1",
                "borderColor": "#f472b6",
                "backgroundColor": "#0b2240",
                "content": "7 = 3 + 4\\n10 = 1 + 2 + 3 + 4\\n12 = 3 + 4 + 5\\n15 = 7 + 8"
              }
            ]
          }
        ]
      }
      ''';

      final result = SlideJsonHelper.parseJson(cardJson);
      expect(result.isSuccess, isTrue);
      expect(result.slides.first.blocks.first.type, SlideBlockType.card);
      expect(result.slides.first.blocks.first.caption, 'Set 1');
      expect(result.slides.first.blocks.first.borderColor, '#f472b6');
      expect(result.slides.first.blocks.first.content, contains('7 = 3 + 4'));
    });

    test('parses columns layout sample with nested mixed content correctly',
        () {
      final result =
          SlideJsonHelper.parseJson(SlideJsonHelper.sampleColumnsLayoutJson);

      expect(result.isSuccess, isTrue);
      final slide = result.slides.first;
      expect(slide.backgroundType, SlideBackgroundType.image);
      expect(slide.backgroundImageUrl, isNotNull);

      final columnsBlock = slide.blocks.firstWhere(
        (b) => b.type == SlideBlockType.columns,
      );
      final decoded = json.decode(columnsBlock.content) as Map<String, dynamic>;
      final columns = decoded['columns'] as List;
      expect(columns.length, 2);

      // Column 1: heading, image, math, bulletList -- a real mix, not
      // just plain text like a table cell would allow.
      final col1 = (columns[0] as List)
          .map((b) => SlideBlock.fromMap(b as Map<String, dynamic>))
          .toList();
      expect(col1.map((b) => b.type), [
        SlideBlockType.heading,
        SlideBlockType.imageUrl,
        SlideBlockType.math,
        SlideBlockType.bulletList,
      ]);

      // Column 2: heading, card, table, bulletList.
      final col2 = (columns[1] as List)
          .map((b) => SlideBlock.fromMap(b as Map<String, dynamic>))
          .toList();
      expect(col2.map((b) => b.type), [
        SlideBlockType.heading,
        SlideBlockType.card,
        SlideBlockType.table,
        SlideBlockType.bulletList,
      ]);
    });

    test('parses banner blocks with layout fields correctly', () {
      const bannerJson = '''
      {
        "title": "Section Break",
        "blocks": [
          {
            "type": "banner",
            "content": "Unit 2: Trigonometry",
            "backgroundColor": "FFF59E0B",
            "textColor": "FF000000",
            "padding": 20,
            "marginVertical": 14,
            "fontSize": 24,
            "horizontalAlign": "center",
            "verticalAlign": "center"
          }
        ]
      }
      ''';

      final result = SlideJsonHelper.parseJson(bannerJson);
      expect(result.isSuccess, isTrue);
      final block = result.slides.first.blocks.first;
      expect(block.type, SlideBlockType.banner);
      expect(block.content, 'Unit 2: Trigonometry');
      expect(block.padding, 20);
      expect(block.marginVertical, 14);
      expect(block.fontSize, 24);
      expect(block.horizontalAlign, 'center');
      expect(block.verticalAlign, 'center');
    });

    test('parses a slide-level contentVerticalAlign for centering a banner',
        () {
      const centeredBannerJson = '''
      {
        "title": "Section Break",
        "contentVerticalAlign": "center",
        "blocks": [
          {
            "type": "banner",
            "content": "Welcome to Chapter 3",
            "horizontalAlign": "center",
            "verticalAlign": "center"
          }
        ]
      }
      ''';

      final result = SlideJsonHelper.parseJson(centeredBannerJson);
      expect(result.isSuccess, isTrue);
      expect(result.slides.first.contentVerticalAlign, 'center');
      expect(result.slides.first.blocks.first.type, SlideBlockType.banner);
    });

    test('contentVerticalAlign defaults to top when absent', () {
      final result =
          SlideJsonHelper.parseJson(SlideJsonHelper.sampleSingleSlideJson);
      expect(result.slides.first.contentVerticalAlign, 'top');
    });
  });
}
