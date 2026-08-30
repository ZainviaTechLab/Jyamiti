import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';

class DrawnLine {
  final List<Offset> path;
  final Color color;
  final double width;
  final bool isHighlighter;

  DrawnLine({
    required this.path,
    required this.color,
    required this.width,
    this.isHighlighter = false,
  });
}

class DrawingCanvasPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final DrawnLine? currentLine;

  DrawingCanvasPainter({
    required this.lines,
    this.currentLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in [...lines, if (currentLine != null) currentLine!]) {
      if (line.path.isEmpty) continue;
      final paint = Paint()
        ..color = line.isHighlighter ? line.color.withOpacity(0.4) : line.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = line.width
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(line.path.first.dx, line.path.first.dy);
      for (int i = 1; i < line.path.length; i++) {
        path.lineTo(line.path[i].dx, line.path[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) => true;
}

class LiveClassroomPresentationScreen extends StatefulWidget {
  final String title;
  final List<dynamic> questions;
  final int initialIndex;
  final String? topicName;
  final String? chapterName;

  const LiveClassroomPresentationScreen({
    super.key,
    required this.title,
    required this.questions,
    this.initialIndex = 0,
    this.topicName,
    this.chapterName,
  });

  @override
  State<LiveClassroomPresentationScreen> createState() =>
      _LiveClassroomPresentationScreenState();
}

class _LiveClassroomPresentationScreenState
    extends State<LiveClassroomPresentationScreen> {
  late int _currentIndex;
  bool _filterClassworkOnly = false;
  List<dynamic> _effectiveQuestions = [];

  // Drawing Canvas State
  bool _isDrawingMode = false;
  final List<DrawnLine> _lines = [];
  DrawnLine? _currentLine;
  Color _selectedColor = const Color(0xFF10B981);
  double _strokeWidth = 4.0;
  bool _isHighlighterMode = false;

  // Question Presentation State
  bool _showHint = false;
  bool _showSolution = false;
  double _fontSize = 22.0; // Adjustable presentation font size

  // Formula Database
  final Map<String, List<Map<String, String>>> _formulas = {
    'Algebra': [
      {'title': 'Quadratic Formula', 'formula': 'x = (-b ± √(b² - 4ac)) / (2a)'},
      {
        'title': 'Algebraic Identities',
        'formula':
            '(a + b)² = a² + 2ab + b²\n(a - b)² = a² - 2ab + b²\na² - b² = (a - b)(a + b)'
      },
      {'title': 'Sum & Product of Roots', 'formula': 'α + β = -b/a,   αβ = c/a'},
    ],
    'Geometry & Trig': [
      {'title': 'Pythagoras Theorem', 'formula': 'a² + b² = c²'},
      {
        'title': 'Trig Identities',
        'formula':
            'sin²θ + cos²θ = 1\n1 + tan²θ = sec²θ\n1 + cot²θ = cosec²θ'
      },
      {
        'title': 'Area Formulas',
        'formula': 'Circle = πr²\nTriangle = ½ × base × height'
      },
    ],
    'Mensuration & Volumes': [
      {
        'title': 'Sphere & Cylinder',
        'formula': 'Sphere Volume = (4/3)πr³\nCylinder Volume = πr²h'
      },
      {
        'title': 'Cone Surface & Volume',
        'formula': 'Cone Volume = (1/3)πr²h\nTotal Surface Area = πr(r + l)'
      },
    ],
  };

  @override
  void initState() {
    super.initState();
    _updateEffectiveQuestions();
    _currentIndex = widget.initialIndex.clamp(
      0,
      _effectiveQuestions.isNotEmpty ? _effectiveQuestions.length - 1 : 0,
    );
  }

  void _updateEffectiveQuestions() {
    if (_filterClassworkOnly) {
      _effectiveQuestions = widget.questions.where((q) {
        if (q is Map) {
          final isClasswork = q['isClasswork'] == true ||
              q['forTutorOnly'] == true ||
              q['isTutorOnly'] == true ||
              q['category'] == 'classwork';
          return isClasswork;
        }
        return false;
      }).toList();
    } else {
      _effectiveQuestions = List.from(widget.questions);
    }
  }

  String _extractQuestionText(dynamic q) {
    if (q == null) return '';
    if (q is String) return q;
    if (q is Map) {
      // Note: `??` only skips null, not empty strings — and fields like
      // descriptiveText default to '' server-side, so they must come
      // *after* the real content fields or an empty descriptiveText would
      // permanently mask a populated `text`/`questionText`.
      for (final candidate in [
        q['questionText'],
        q['question'],
        q['title'],
        q['text'],
        q['descriptiveText'],
      ]) {
        final s = candidate?.toString().trim() ?? '';
        if (s.isNotEmpty) return s;
      }
      return '';
    }
    return q.toString();
  }

  String _extractSolutionText(dynamic q) {
    if (q is Map) {
      return (q['solution'] ??
              q['solutionText'] ??
              q['explanation'] ??
              q['answer'] ??
              '')
          .toString();
    }
    return '';
  }

  String _extractHintText(dynamic q) {
    if (q is Map) {
      return (q['hint'] ?? q['hintText'] ?? q['keyFormula'] ?? '').toString();
    }
    return '';
  }

  List<String> _extractOptions(dynamic q) {
    if (q is Map && q['options'] is List) {
      return (q['options'] as List).map((e) {
        // Options come in two shapes depending on the source: plain
        // strings (Question model) or {text, imageUrl, isSvg} objects
        // (AssessmentQuestion / Course practice questions). Calling
        // e.toString() on the latter dumped the raw Map representation
        // onto the smartboard instead of the option text.
        if (e is String) return e;
        if (e is Map) {
          final text = (e['text'] ?? '').toString().trim();
          if (text.isNotEmpty) return text;
          final imageUrl = (e['imageUrl'] ?? '').toString().trim();
          if (imageUrl.isNotEmpty) return '[Image]';
          return '';
        }
        return e.toString();
      }).toList();
    }
    return [];
  }

  bool _isClassworkQuestion(dynamic q) {
    if (q is Map) {
      return q['isClasswork'] == true ||
          q['forTutorOnly'] == true ||
          q['isTutorOnly'] == true ||
          q['category'] == 'classwork';
    }
    return false;
  }

  void _showFormulasSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.functions_rounded,
                    color: Color(0xFF6366F1), size: 24),
                const SizedBox(width: 10),
                Text(
                  '📐 Quick Formula Reference Sheet',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 20),
            Expanded(
              child: ListView(
                children: _formulas.entries.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF10B981),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...entry.value.map(
                          (f) => Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        f['title'] ?? '',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        f['formula'] ?? '',
                                        style: GoogleFonts.firaCode(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentQ = _effectiveQuestions.isNotEmpty &&
            _currentIndex < _effectiveQuestions.length
        ? _effectiveQuestions[_currentIndex]
        : null;

    final qText = _extractQuestionText(currentQ);
    final solText = _extractSolutionText(currentQ);
    final hintText = _extractHintText(currentQ);
    final options = _extractOptions(currentQ);
    final isClasswork = _isClassworkQuestion(currentQ);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Stack(
          children: [
            // Main Presentation Canvas
            Column(
              children: [
                // Top Header Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.9),
                    border: const Border(
                      bottom: BorderSide(color: Colors.white12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.tv_rounded,
                          color: Color(0xFF6366F1),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.topicName != null)
                              Text(
                                '${widget.chapterName != null ? "${widget.chapterName} • " : ""}${widget.topicName}',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),

                      // Filter Classwork Only Toggle Button
                      FilterChip(
                        selected: _filterClassworkOnly,
                        onSelected: (val) {
                          setState(() {
                            _filterClassworkOnly = val;
                            _updateEffectiveQuestions();
                            _currentIndex = 0;
                            _lines.clear();
                          });
                        },
                        avatar: Icon(
                          Icons.school_rounded,
                          size: 16,
                          color: _filterClassworkOnly
                              ? Colors.white
                              : const Color(0xFF10B981),
                        ),
                        label: Text(
                          _filterClassworkOnly
                              ? 'Classwork Only (${_effectiveQuestions.length})'
                              : 'All Questions (${_effectiveQuestions.length})',
                          style: TextStyle(
                            color: _filterClassworkOnly
                                ? Colors.white
                                : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        selectedColor: const Color(0xFF10B981),
                        backgroundColor: const Color(0xFF1E293B),
                      ),
                      const SizedBox(width: 12),

                      // Exit Presentation Mode Button
                      IconButton(
                        icon: const Icon(Icons.fullscreen_exit_rounded,
                            color: Colors.redAccent, size: 24),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Exit Presentation Mode',
                      ),
                    ],
                  ),
                ),

                // Question Area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: _effectiveQuestions.isEmpty
                        ? const Center(
                            child: Text(
                              'No questions available in this filter.',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 18),
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Question Badge & Indicator Bar
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1)
                                            .withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: const Color(0xFF6366F1)),
                                      ),
                                      child: Text(
                                        'QUESTION ${_currentIndex + 1} OF ${_effectiveQuestions.length}',
                                        style: GoogleFonts.firaCode(
                                          color: const Color(0xFF818CF8),
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    if (isClasswork)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981)
                                              .withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: const Color(0xFF10B981)),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.stars_rounded,
                                                color: Color(0xFF10B981),
                                                size: 14),
                                            SizedBox(width: 4),
                                            Text(
                                              '👨‍🏫 CLASSWORK (TUTOR ONLY)',
                                              style: TextStyle(
                                                color: Color(0xFF10B981),
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Large Presentation Question Card
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white12),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 15,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(
                                        qText.isNotEmpty
                                            ? qText
                                            : 'No question text provided.',
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: _fontSize,
                                          height: 1.4,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),

                                      // Options Grid / List
                                      if (options.isNotEmpty) ...[
                                        const SizedBox(height: 24),
                                        const Divider(color: Colors.white10),
                                        const SizedBox(height: 12),
                                        for (int i = 0;
                                            i < options.length;
                                            i++)
                                          Container(
                                            margin: const EdgeInsets.only(
                                                bottom: 10),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0F172A),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                  color: Colors.white12),
                                            ),
                                            child: Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 14,
                                                  backgroundColor:
                                                      const Color(0xFF6366F1)
                                                          .withOpacity(0.2),
                                                  child: Text(
                                                    String.fromCharCode(
                                                        65 + i),
                                                    style: const TextStyle(
                                                      color: Color(0xFF818CF8),
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: Text(
                                                    options[i],
                                                    style: GoogleFonts.outfit(
                                                      color: Colors.white
                                                          .withOpacity(0.9),
                                                      fontSize:
                                                          _fontSize * 0.85,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Hint & Solution Reveal Section
                                Row(
                                  children: [
                                    if (hintText.isNotEmpty)
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          setState(() => _showHint = !_showHint);
                                        },
                                        icon: Icon(
                                          _showHint
                                              ? Icons.lightbulb
                                              : Icons.lightbulb_outline,
                                          color: Colors.amber,
                                          size: 18,
                                        ),
                                        label: Text(_showHint
                                            ? 'Hide Hint'
                                            : '💡 Reveal Hint'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.amber,
                                          side: const BorderSide(
                                              color: Colors.amber),
                                        ),
                                      ),
                                    const SizedBox(width: 12),
                                    if (solText.isNotEmpty)
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          setState(
                                              () => _showSolution = !_showSolution);
                                        },
                                        icon: Icon(
                                          _showSolution
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          size: 18,
                                        ),
                                        label: Text(_showSolution
                                            ? 'Hide Solution'
                                            : '📝 Reveal Solution'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF10B981),
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                  ],
                                ),

                                if (_showHint && hintText.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Colors.amber.withOpacity(0.4)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.lightbulb_rounded,
                                            color: Colors.amber, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'HINT: $hintText',
                                            style: const TextStyle(
                                              color: Colors.amber,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                if (_showSolution && solText.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0xFF10B981)
                                              .withOpacity(0.4)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.check_circle_rounded,
                                                color: Color(0xFF10B981),
                                                size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'STEP-BY-STEP SOLUTION:',
                                              style: TextStyle(
                                                color: Color(0xFF10B981),
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        SelectableText(
                                          solText,
                                          style: GoogleFonts.firaCode(
                                            color: Colors.white,
                                            fontSize: 14,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 100), // Spacing for floating bottom bar
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),

            // Drawing Canvas Overlay when Drawing Mode is active
            if (_isDrawingMode)
              Positioned.fill(
                child: GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      _currentLine = DrawnLine(
                        path: [details.localPosition],
                        color: _selectedColor,
                        width: _strokeWidth,
                        isHighlighter: _isHighlighterMode,
                      );
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      if (_currentLine != null) {
                        final updatedPath =
                            List<Offset>.from(_currentLine!.path)
                              ..add(details.localPosition);
                        _currentLine = DrawnLine(
                          path: updatedPath,
                          color: _selectedColor,
                          width: _strokeWidth,
                          isHighlighter: _isHighlighterMode,
                        );
                      }
                    });
                  },
                  onPanEnd: (_) {
                    setState(() {
                      if (_currentLine != null) {
                        _lines.add(_currentLine!);
                        _currentLine = null;
                      }
                    });
                  },
                  child: CustomPaint(
                    painter: DrawingCanvasPainter(
                      lines: _lines,
                      currentLine: _currentLine,
                    ),
                  ),
                ),
              ),

            // Bottom Floating Controls Toolbar
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Previous Question Button
                          ElevatedButton.icon(
                            onPressed: _currentIndex > 0
                                ? () {
                                    setState(() {
                                      _currentIndex--;
                                      _showHint = false;
                                      _showSolution = false;
                                      _lines.clear();
                                    });
                                  }
                                : null,
                            icon: const Icon(Icons.arrow_back_rounded, size: 18),
                            label: const Text('Prev'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Next Question Button
                          ElevatedButton.icon(
                            onPressed: _currentIndex <
                                    _effectiveQuestions.length - 1
                                ? () {
                                    setState(() {
                                      _currentIndex++;
                                      _showHint = false;
                                      _showSolution = false;
                                      _lines.clear();
                                    });
                                  }
                                : null,
                            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                            label: const Text('Next'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const VerticalDivider(
                              color: Colors.white24, width: 24),

                          // Drawing Mode Toggle
                          IconButton(
                            icon: Icon(
                              _isDrawingMode
                                  ? Icons.gesture
                                  : Icons.edit_outlined,
                              color: _isDrawingMode
                                  ? const Color(0xFF10B981)
                                  : Colors.white70,
                            ),
                            onPressed: () {
                              setState(() {
                                _isDrawingMode = !_isDrawingMode;
                              });
                            },
                            tooltip: _isDrawingMode
                                ? 'Exit Drawing Mode'
                                : 'Enable Whiteboard Pen',
                          ),

                          // Color Picker Buttons when in Drawing Mode
                          if (_isDrawingMode) ...[
                            for (var color in [
                              const Color(0xFF10B981),
                              const Color(0xFFEF4444),
                              const Color(0xFFF59E0B),
                              const Color(0xFF3B82F6),
                              Colors.white,
                            ])
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedColor = color;
                                  });
                                },
                                child: Container(
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _selectedColor == color
                                          ? Colors.white
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            IconButton(
                              icon: Icon(
                                Icons.brush,
                                color: _isHighlighterMode
                                    ? Colors.amber
                                    : Colors.white54,
                                size: 18,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isHighlighterMode = !_isHighlighterMode;
                                });
                              },
                              tooltip: 'Highlighter Mode',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_sweep_rounded,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () {
                                setState(() {
                                  _lines.clear();
                                });
                              },
                              tooltip: 'Clear Drawings',
                            ),
                          ],

                          const VerticalDivider(
                              color: Colors.white24, width: 24),

                          // Font Size Zoom Controls
                          IconButton(
                            icon: const Icon(Icons.zoom_out_rounded,
                                color: Colors.white70, size: 20),
                            onPressed: () {
                              if (_fontSize > 16) {
                                setState(() => _fontSize -= 2);
                              }
                            },
                            tooltip: 'Decrease Font Size',
                          ),
                          Text(
                            '${_fontSize.toInt()}pt',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                          IconButton(
                            icon: const Icon(Icons.zoom_in_rounded,
                                color: Colors.white70, size: 20),
                            onPressed: () {
                              if (_fontSize < 40) {
                                setState(() => _fontSize += 2);
                              }
                            },
                            tooltip: 'Increase Font Size',
                          ),

                          const VerticalDivider(
                              color: Colors.white24, width: 24),

                          // Quick Formula Lookup Sheet
                          OutlinedButton.icon(
                            onPressed: _showFormulasSheet,
                            icon: const Icon(Icons.functions_rounded,
                                size: 16, color: Color(0xFF6366F1)),
                            label: const Text('📐 Formulas'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF6366F1),
                              side: const BorderSide(color: Color(0xFF6366F1)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
