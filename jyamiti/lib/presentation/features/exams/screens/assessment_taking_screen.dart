import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:math_keyboard/math_keyboard.dart';
import '../../../../services/api_service.dart';
import '../../../../widgets/latex_rich_text.dart';
import '../../../../widgets/svg_label_overlay.dart';
import '../../../../providers/theme_provider.dart';
// import '../../../../widgets/writing_pad_widget.dart';
import 'package:lottie/lottie.dart';
import 'package:math_expressions/math_expressions.dart';

import 'package:file_picker/file_picker.dart';
import '../../../../services/deepseek_service.dart';
import '../../../widgets/writing_pad_widget.dart' show WritingPadWidget;

class AssessmentTakingScreen extends StatefulWidget {
  final Map<String, dynamic>? trySingleQuestion;
  final List<dynamic>? practiceQuestions;
  final String? assignmentId;
  final VoidCallback? onCompleted;

  const AssessmentTakingScreen({
    super.key,
    this.trySingleQuestion,
    this.practiceQuestions,
    this.assignmentId,
    this.onCompleted,
  });

  @override
  State<AssessmentTakingScreen> createState() => _AssessmentTakingScreenState();
}

class _AssessmentTakingScreenState extends State<AssessmentTakingScreen> {
  // Current screen phase: 1 = Registration, 2 = Test, 3 = Score/Completion
  int _currentPhase = 1;
  bool _showWritingPad = true;
  bool _isWritingPadFullScreen = false;
  final GlobalKey _writingPadKey = GlobalKey();

  // Registration Controller State
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  int _selectedGrade = 1;

  // Test State
  List<dynamic> _questions = [];
  int _currentQuestionIndex = 0;
  bool _isLoading = false;
  bool _isCheckingPhone = false;
  String? _errorMessage;
  String _practiceViewMode = 'STUDENT'; // 'STUDENT' or 'TUTOR'

  // Answers State
  Map<int, List<String>> _selectedAnswers =
      {}; // questionIndex -> list of answers/indices
  Map<int, bool> _questionFeedback =
      {}; // questionIndex -> answered correctness
  bool _hasSubmittedCurrentQuestion = false;

  // Scoring
  int _score = 0;

  String _selectedCelebrationLottie = 'assets/image/celebration.json';
  final List<String> _celebrationLotties = [
    'assets/image/celebration.json',
    'assets/image/Fireworks.json',
    'assets/image/Red White & Blue Fireworks.json',
    'assets/image/Fireworks Teal and Red.json',
    'assets/image/Right Answer.json',
    'assets/image/Right Answer.json',
    'assets/image/Thumb Up Party.json',
  ];

  // Ordering question options
  List<dynamic> _orderingOptions = [];

  // Matching question right-side options
  List<dynamic> _matchingRightOptions = [];

  // Geometric Construction question lines
  List<LineState> _geometryLines = [];

  // Audio player
  late AudioPlayer _audioPlayer;
  final Random _random = Random();

  static const List<String> _correctSounds = [
    'sound/right-answer-1.mp3',
    // 'sound/right-answer-2.mp3',
    'sound/right-answer-3.wav',
    'sound/right-answer-4.wav',
  ];

  static const List<String> _wrongSounds = [
    'sound/wrong-answer-1.mp3',
    'sound/wrong-answer-2.mp3',
  ];

  // Short Answer Focus Node & Hint display state
  late FocusNode _shortAnswerFocusNode;
  bool _showShortAnswerHint = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _shortAnswerFocusNode = FocusNode();
    _shortAnswerFocusNode.addListener(_updateHintVisibility);
    if (widget.trySingleQuestion != null) {
      _questions = [widget.trySingleQuestion];
      _currentQuestionIndex = 0;
      _currentPhase = 2;
      _loadQuestion(0);
    } else if (widget.practiceQuestions != null) {
      _questions = widget.practiceQuestions!;
      _currentQuestionIndex = 0;
      _currentPhase = 2;
      _loadQuestion(0);
    } else {
      _loadSavedProgress();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _whatsappCtrl.dispose();
    _audioPlayer.dispose();
    _shortAnswerFocusNode.removeListener(_updateHintVisibility);
    _shortAnswerFocusNode.dispose();
    super.dispose();
  }

  void _updateHintVisibility() {
    if (_questions.isEmpty || _currentQuestionIndex >= _questions.length)
      return;
    final q = _questions[_currentQuestionIndex];
    if (q['type'] != 'SHORT_ANSWER') return;

    final String hint = q['shortAnswerHint'] ?? '';
    if (hint.isEmpty) {
      if (_showShortAnswerHint) {
        setState(() => _showShortAnswerHint = false);
      }
      return;
    }

    final currentAnswersList = _selectedAnswers[_currentQuestionIndex] ?? [];
    final String text = currentAnswersList.isNotEmpty
        ? currentAnswersList.first
        : '';
    final bool hasFocus = _shortAnswerFocusNode.hasFocus;
    final bool isEmpty = text.isEmpty;

    final bool newVisibility = hasFocus && isEmpty;
    if (_showShortAnswerHint != newVisibility) {
      setState(() {
        _showShortAnswerHint = newVisibility;
      });
    }
  }

  // Get dynamic image server URL
  String _getImageUrl(String relativeUrl) {
    if (relativeUrl.isEmpty) return '';
    if (relativeUrl.startsWith('http://') ||
        relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }
    String origin = ApiService.baseUrl;
    if (origin.endsWith('/api')) {
      origin = origin.substring(0, origin.length - 4);
    }
    return '$origin/$relativeUrl';
  }

  bool _isLatex(String text) {
    final clean = text.trim();
    return clean.contains('\\') ||
        clean.contains('^') ||
        clean.contains('_') ||
        clean.contains('{') ||
        clean.contains('}');
  }

  String _normalizeLatex(String text) {
    String normalized = text.trim();
    if (normalized.startsWith('\$') && normalized.endsWith('\$')) {
      if (normalized.length > 1) {
        normalized = normalized.substring(1, normalized.length - 1).trim();
      }
    }
    // Replace multiple whitespaces with single space
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
    // Remove spaces around common delimiters, math symbols, and backslashes
    normalized = normalized.replaceAll(
      RegExp(r'\s*([\{\}\[\]\(\)\+\-\*\/\=\^\_\,\\])\s*'),
      '\$1',
    );
    return normalized.toLowerCase().trim();
  }

  String _normalizeAnswer(String ans) {
    String trimmed = ans.trim();
    if (_isLatex(trimmed)) {
      return _normalizeLatex(trimmed);
    }
    return trimmed.toLowerCase();
  }

  String _latexToNormalMath(String latex) {
    String math = latex.trim();
    if (math.startsWith('\$') && math.endsWith('\$')) {
      if (math.length > 1) {
        math = math.substring(1, math.length - 1).trim();
      }
    }

    math = math.replaceAll(r'\left(', '(');
    math = math.replaceAll(r'\right)', ')');
    math = math.replaceAll(r'\left[', '[');
    math = math.replaceAll(r'\right]', ']');
    math = math.replaceAll(r'\times', '*');
    math = math.replaceAll(r'\div', '/');
    math = math.replaceAll(r'\pi', '3.14159265358979323846');

    final fracRegex = RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}');
    while (fracRegex.hasMatch(math)) {
      math = math.replaceAllMapped(fracRegex, (m) {
        return '((${m.group(1)})/(${m.group(2)}))';
      });
    }

    math = math.replaceAllMapped(RegExp(r'\^\{([^{}]+)\}'), (m) {
      return '^(${m.group(1)})';
    });

    math = math.replaceAll(RegExp(r'\\[a-zA-Z]+'), '');
    math = math.replaceAll(r'\', '');
    return math;
  }

  String _insertExplicitMultiplication(String expr) {
    String res = expr;
    res = res.replaceAllMapped(RegExp(r'(\d+)([a-zA-Z])'), (m) {
      return '${m.group(1)}*${m.group(2)}';
    });
    res = res.replaceAllMapped(RegExp(r'(\d+)\('), (m) {
      return '${m.group(1)}*(';
    });
    res = res.replaceAll(r')(', r')*(');
    res = res.replaceAllMapped(RegExp(r'\)([a-zA-Z])'), (m) {
      return ')*${m.group(1)}';
    });
    res = res.replaceAllMapped(RegExp(r'([a-zA-Z])\('), (m) {
      return '${m.group(1)}*(';
    });
    return res;
  }

  String _normalizeAnswerStringForEval(String ans) {
    String processed = ans.trim();
    if (_isLatex(processed)) {
      processed = _latexToNormalMath(processed);
    }
    processed = processed.replaceAll(' ', '');
    processed = _insertExplicitMultiplication(processed);
    return processed.toLowerCase();
  }

  void _findVariables(Expression exp, Set<String> vars) {
    if (exp is Variable) {
      vars.add(exp.name);
    } else if (exp is BinaryOperator) {
      _findVariables(exp.first, vars);
      _findVariables(exp.second, vars);
    } else if (exp is UnaryOperator) {
      _findVariables(exp.exp, vars);
    }
  }

  bool _areAnswersEquivalent(String ans1, String ans2) {
    final clean1 = _normalizeAnswerStringForEval(ans1);
    final clean2 = _normalizeAnswerStringForEval(ans2);
    if (clean1 == clean2) return true;

    try {
      Parser p = Parser();
      Expression exp1 = p.parse(clean1);
      Expression exp2 = p.parse(clean2);

      final vars = <String>{};
      _findVariables(exp1, vars);
      _findVariables(exp2, vars);

      if (vars.isEmpty) {
        ContextModel cm = ContextModel();
        final double val1 = exp1.evaluate(EvaluationType.REAL, cm);
        final double val2 = exp2.evaluate(EvaluationType.REAL, cm);
        return (val1 - val2).abs() < 1e-7;
      } else {
        final points = [
          {for (var v in vars) v: 1.5},
          {for (var v in vars) v: -2.3},
          {for (var v in vars) v: 5.7},
        ];

        for (final pt in points) {
          ContextModel cm = ContextModel();
          for (final entry in pt.entries) {
            cm.bindVariable(Variable(entry.key), Number(entry.value));
          }
          final double val1 = exp1.evaluate(EvaluationType.REAL, cm);
          final double val2 = exp2.evaluate(EvaluationType.REAL, cm);
          if ((val1 - val2).abs() > 1e-7) {
            return false;
          }
        }
        return true;
      }
    } catch (_) {
      return clean1 == clean2;
    }
  }

  bool _isUnsimplifiedFraction(String studentAns, String correctAns) {
    try {
      if (!_areAnswersEquivalent(studentAns, correctAns)) return false;
      final cleanStudent = _normalizeAnswerStringForEval(studentAns);
      final cleanCorrect = _normalizeAnswerStringForEval(correctAns);
      if (cleanStudent == cleanCorrect) return false;
      final RegExp numRegex = RegExp(r'\d+');
      final studentNumbers = numRegex
          .allMatches(cleanStudent)
          .map((m) => int.parse(m.group(0)!))
          .toList();
      final correctNumbers = numRegex
          .allMatches(cleanCorrect)
          .map((m) => int.parse(m.group(0)!))
          .toList();
      if (studentNumbers.isNotEmpty && correctNumbers.isNotEmpty) {
        int maxStudent = studentNumbers.reduce((a, b) => a > b ? a : b);
        int maxCorrect = correctNumbers.reduce((a, b) => a > b ? a : b);
        if (maxStudent > maxCorrect) {
          if (cleanStudent.contains('/') ||
              cleanStudent.contains(r'\frac') ||
              cleanCorrect.contains('/')) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _showMathDialog(int questionIdx, {int? inputIdx}) async {
    String currentMath = '';

    // If there's an existing answer, prefill it!
    if (inputIdx != null) {
      if (_selectedAnswers[questionIdx] != null &&
          _selectedAnswers[questionIdx]!.length > inputIdx) {
        currentMath = _selectedAnswers[questionIdx]![inputIdx];
      }
    } else {
      if (_selectedAnswers[questionIdx] != null &&
          _selectedAnswers[questionIdx]!.isNotEmpty) {
        currentMath = _selectedAnswers[questionIdx]![0];
      }
    }

    final mathController = MathFieldEditingController();
    if (currentMath.isNotEmpty) {
      try {
        mathController.updateValue(TeXParser(currentMath).parse());
      } catch (_) {
        // Fallback if conversion fails
      }
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark
            ? const Color(0xFF1E293B)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Insert Math Equation',
          style: TextStyle(
            color: context.textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: MathField(
            controller: mathController,
            variables: const ['x', 'y', 'z'],
            keyboardType: MathKeyboardType.expression,
            decoration: InputDecoration(
              hintText: 'Use math keyboard...',
              hintStyle: TextStyle(color: context.textColor54.withOpacity(0.5)),
              border: InputBorder.none,
            ),
            onChanged: (val) {
              currentMath = val;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx, currentMath);
            },
            child: Text('Insert', style: TextStyle(color: context.textColor)),
          ),
        ],
      ),
    );

    mathController.dispose();

    if (result != null) {
      setState(() {
        if (inputIdx != null) {
          while (_selectedAnswers[questionIdx]!.length <= inputIdx) {
            _selectedAnswers[questionIdx]!.add("");
          }
          _selectedAnswers[questionIdx]![inputIdx] = result;
        } else {
          _selectedAnswers[questionIdx] = [result];
        }
      });
      _saveProgress();
    }
  }

  // Save progress state using SharedPreferences
  Future<void> _saveProgress() async {
    if (widget.trySingleQuestion != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('assessment_phase', _currentPhase);
      await prefs.setString('assessment_name', _nameCtrl.text.trim());
      await prefs.setString('assessment_whatsapp', _whatsappCtrl.text.trim());
      await prefs.setInt('assessment_grade', _selectedGrade);
      await prefs.setString('assessment_questions', jsonEncode(_questions));
      await prefs.setInt('assessment_current_index', _currentQuestionIndex);

      // Convert Map<int, List<String>> to Map<String, List<String>> for JSON
      final Map<String, List<String>> selAnsStringMap = _selectedAnswers.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      await prefs.setString(
        'assessment_selected_answers',
        jsonEncode(selAnsStringMap),
      );

      // Convert Map<int, bool> to Map<String, bool> for JSON
      final Map<String, bool> feedbackStringMap = _questionFeedback.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      await prefs.setString(
        'assessment_feedback',
        jsonEncode(feedbackStringMap),
      );

      await prefs.setBool(
        'assessment_has_submitted',
        _hasSubmittedCurrentQuestion,
      );
      await prefs.setInt('assessment_score', _score);

      if (_orderingOptions.isNotEmpty) {
        await prefs.setString(
          'assessment_ordering_options',
          jsonEncode(_orderingOptions),
        );
      } else {
        await prefs.remove('assessment_ordering_options');
      }

      if (_matchingRightOptions.isNotEmpty) {
        await prefs.setString(
          'assessment_matching_right_options',
          jsonEncode(_matchingRightOptions),
        );
      } else {
        await prefs.remove('assessment_matching_right_options');
      }
    } catch (e) {
      debugPrint('Error saving assessment progress: $e');
    }
  }

  // Clear saved progress state on test finalization
  Future<void> _clearSavedProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('assessment_phase');
      await prefs.remove('assessment_name');
      await prefs.remove('assessment_whatsapp');
      await prefs.remove('assessment_grade');
      await prefs.remove('assessment_questions');
      await prefs.remove('assessment_current_index');
      await prefs.remove('assessment_selected_answers');
      await prefs.remove('assessment_feedback');
      await prefs.remove('assessment_has_submitted');
      await prefs.remove('assessment_score');
      await prefs.remove('assessment_ordering_options');
      await prefs.remove('assessment_matching_right_options');
    } catch (e) {
      debugPrint('Error clearing assessment progress: $e');
    }
  }

  // Load saved progress state if they return to the screen
  Future<void> _loadSavedProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPhase = prefs.getInt('assessment_phase');
      if (savedPhase == 2) {
        final savedName = prefs.getString('assessment_name') ?? '';
        final savedWhatsapp = prefs.getString('assessment_whatsapp') ?? '';
        final savedGrade = prefs.getInt('assessment_grade') ?? 1;
        final questionsJson = prefs.getString('assessment_questions');

        if (questionsJson != null) {
          final List<dynamic> savedQuestions = jsonDecode(questionsJson);
          if (savedQuestions.isNotEmpty) {
            final savedIndex = prefs.getInt('assessment_current_index') ?? 0;
            final savedScore = prefs.getInt('assessment_score') ?? 0;
            final savedHasSubmitted =
                prefs.getBool('assessment_has_submitted') ?? false;

            Map<int, List<String>> selectedAns = {};
            final String? selAnsJson = prefs.getString(
              'assessment_selected_answers',
            );
            if (selAnsJson != null) {
              final Map<String, dynamic> rawMap = jsonDecode(selAnsJson);
              selectedAns = rawMap.map(
                (key, val) => MapEntry(int.parse(key), List<String>.from(val)),
              );
            }

            Map<int, bool> feedback = {};
            final String? feedbackJson = prefs.getString('assessment_feedback');
            if (feedbackJson != null) {
              final Map<String, dynamic> rawMap = jsonDecode(feedbackJson);
              feedback = rawMap.map(
                (key, val) => MapEntry(int.parse(key), val as bool),
              );
            }

            List<dynamic> ordOptions = [];
            final String? orderingJson = prefs.getString(
              'assessment_ordering_options',
            );
            if (orderingJson != null) {
              ordOptions = jsonDecode(orderingJson);
            }

            List<dynamic> matOptions = [];
            final String? matchingJson = prefs.getString(
              'assessment_matching_right_options',
            );
            if (matchingJson != null) {
              matOptions = jsonDecode(matchingJson);
            }

            setState(() {
              _nameCtrl.text = savedName;
              _whatsappCtrl.text = savedWhatsapp;
              _selectedGrade = savedGrade;
              _questions = savedQuestions;
              _currentQuestionIndex = savedIndex;
              _score = savedScore;
              _hasSubmittedCurrentQuestion = savedHasSubmitted;
              _selectedAnswers = selectedAns;
              _questionFeedback = feedback;
              _orderingOptions = ordOptions;
              _matchingRightOptions = matOptions;

              _loadQuestionForResume(savedIndex);

              _currentPhase = 2;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading assessment progress: $e');
    }
  }

  void _loadQuestionForResume(int index) {
    if (_questions.isEmpty || index >= _questions.length) return;
    final q = _questions[index];

    if (q['type'] == 'ORDERING' && _orderingOptions.isEmpty) {
      _orderingOptions = List.from(q['options']);
      _orderingOptions.shuffle();
      final List<dynamic> dbOptions = q['options'];
      _selectedAnswers[index] = _orderingOptions.map((opt) {
        return dbOptions.indexOf(opt).toString();
      }).toList();
    } else if (q['type'] == 'MATCHING' && _matchingRightOptions.isEmpty) {
      _matchingRightOptions = List.from(q['rightOptions'] ?? []);
      _matchingRightOptions.shuffle();
      final List<dynamic> dbRight = q['rightOptions'] ?? [];
      _selectedAnswers[index] = _matchingRightOptions.map((opt) {
        return dbRight.indexOf(opt).toString();
      }).toList();
    } else if (q['type'] == 'GEOMETRIC') {
      final int linesCount = q['geometryLinesCount'] as int? ?? 1;
      _geometryLines = List.generate(linesCount, (i) {
        final double yOffset = 0.82 + (i * 0.08);
        return LineState(
          p1: Offset(0.15 + (i * 0.05), yOffset),
          p2: Offset(0.85 - (i * 0.05), yOffset),
        );
      });
      if (_selectedAnswers[index] == null) {
        _selectedAnswers[index] = [];
      }
    }
  }

  // Play audio chime
  void _playCorrectSound() async {
    try {
      final String soundFile =
          _correctSounds[_random.nextInt(_correctSounds.length)];
      await _audioPlayer.play(AssetSource(soundFile));
    } catch (e) {
      debugPrint('Audio playback error: $e');
    }
  }

  void _playWrongSound() async {
    try {
      final String soundFile =
          _wrongSounds[_random.nextInt(_wrongSounds.length)];
      await _audioPlayer.play(AssetSource(soundFile));
    } catch (e) {
      debugPrint('Audio playback error: $e');
    }
  }

  void _loadQuestion(int index) {
    if (_questions.isEmpty || index >= _questions.length) return;

    setState(() {
      _showShortAnswerHint = false;
    });

    final q = _questions[index];
    if (q['type'] == 'ORDERING') {
      _orderingOptions = List.from(q['options']);
      _orderingOptions.shuffle();

      // Default selection (current shuffled sequence)
      final List<dynamic> dbOptions = q['options'];
      _selectedAnswers[index] = _orderingOptions.map((opt) {
        return dbOptions.indexOf(opt).toString();
      }).toList();
    } else if (q['type'] == 'MATCHING') {
      _matchingRightOptions = List.from(q['rightOptions'] ?? []);
      _matchingRightOptions.shuffle();

      // Default selection (current shuffled right options mapping to left options)
      final List<dynamic> dbRight = q['rightOptions'] ?? [];
      _selectedAnswers[index] = _matchingRightOptions.map((opt) {
        return dbRight.indexOf(opt).toString();
      }).toList();
    } else if (q['type'] == 'GEOMETRIC') {
      final int linesCount = q['geometryLinesCount'] as int? ?? 1;
      _geometryLines = List.generate(linesCount, (i) {
        final double yOffset = 0.82 + (i * 0.08);
        return LineState(
          p1: Offset(0.15 + (i * 0.05), yOffset),
          p2: Offset(0.85 - (i * 0.05), yOffset),
        );
      });
      _selectedAnswers[index] = [];
    } else if (q['type'] == 'MATRIX_MCQ') {
      final List<dynamic> rows = q['options'] ?? [];
      _selectedAnswers[index] = List.generate(rows.length, (idx) => "");
    } else if (q['type'] == 'MATRIX_INPUT') {
      final List<dynamic> rows = q['options'] ?? [];
      int inputCount = 0;
      for (var row in rows) {
        final String jsonStr = row['text'] ?? '[]';
        List<dynamic> cells = [];
        try {
          cells = json.decode(jsonStr);
        } catch (_) {}
        for (var cell in cells) {
          if (cell['isInput'] == true) {
            inputCount++;
          }
        }
      }
      _selectedAnswers[index] = List.generate(inputCount, (idx) => "");
    } else if (q['type'] == 'EQUATION') {
      final List<dynamic> steps = q['options'] ?? [];
      int inputCount = 0;
      final regExp = RegExp(r'\[INPUT:(.*?)\]');
      for (var step in steps) {
        final String stepText = step['text'] ?? '';
        final Iterable<Match> matches = regExp.allMatches(stepText);
        inputCount += matches.length;
      }
      _selectedAnswers[index] = List.generate(inputCount, (idx) => "");
    } else if (q['type'] == 'STATEMENT_DROPDOWN') {
      final List<dynamic> statements = q['options'] ?? [];
      int selectCount = 0;
      final regExp = RegExp(r'\[SELECT:(.*?):(.*?)\]');
      for (var stmt in statements) {
        final String stmtText = stmt['text'] ?? '';
        final Iterable<Match> matches = regExp.allMatches(stmtText);
        selectCount += matches.length;
      }
      _selectedAnswers[index] = List.generate(selectCount, (idx) => "");
    } else if (q['type'] == 'INLINE_SELECT') {
      final String text = q['text'] ?? '';
      int selectCount = 0;
      final regExp = RegExp(r'\[SELECT:(.*?):(.*?)\]');
      final Iterable<Match> matches = regExp.allMatches(text);
      selectCount += matches.length;
      _selectedAnswers[index] = List.generate(selectCount, (idx) => "");
    } else if (q['type'] == 'FILL_IN_BLANKS') {
      final String text = q['text'] ?? '';
      int blankCount = 0;
      final regExp = RegExp(r'\[(?:BLANK|INPUT)(?::([^\]]*))?\]', caseSensitive: false);
      final Iterable<Match> matches = regExp.allMatches(text);
      blankCount = matches.length;
      if (blankCount == 0 && q['correctAnswers'] is List) {
        blankCount = (q['correctAnswers'] as List).length;
      }
      _selectedAnswers[index] = List.generate(blankCount, (idx) => "");
    } else if (q['type'] == 'DESCRIPTIVE') {
      _selectedAnswers[index] = ["", "", ""];
    }
  }

  // Registration & Phone Check
  Future<void> _startTest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCheckingPhone = true;
      _errorMessage = null;
    });

    final number = _whatsappCtrl.text.trim();
    try {
      // Check phone duplicate in backend
      final checkRes = await ApiService.get(
        '/assessment-submissions/check-phone/$number',
      );
      if (checkRes.statusCode == 200) {
        final data = jsonDecode(checkRes.body);
        if (data['taken'] == true) {
          setState(() {
            _errorMessage = 'you already taken the test';
            _isCheckingPhone = false;
          });
          return;
        }
      }

      // Fetch questions for selected grade
      final qRes = await ApiService.get(
        '/assessment-questions/grade/$_selectedGrade',
      );
      if (qRes.statusCode == 200) {
        final List<dynamic> fetched = jsonDecode(qRes.body);
        if (fetched.isEmpty) {
          setState(() {
            _errorMessage =
                'No questions available for Grade $_selectedGrade yet. Please contact admin.';
            _isCheckingPhone = false;
          });
          return;
        }

        setState(() {
          _questions = fetched;
          _currentQuestionIndex = 0;
          _selectedAnswers.clear();
          _questionFeedback.clear();
          _hasSubmittedCurrentQuestion = false;
          _score = 0;
          _loadQuestion(0);
          _currentPhase = 2; // Transition to test
          _isCheckingPhone = false;
        });
        _saveProgress();
      } else {
        setState(() {
          _errorMessage =
              'Failed to fetch assessment questions. Try again later.';
          _isCheckingPhone = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network connection error. Please try again.';
        _isCheckingPhone = false;
      });
    }
  }

  // Question Submission Logic
  Future<void> _submitAnswer() async {
    if (_questions.isEmpty || _hasSubmittedCurrentQuestion) return;

    final q = _questions[_currentQuestionIndex];
    final selected = _selectedAnswers[_currentQuestionIndex] ?? [];

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or write an answer first!'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    bool correct = false;
    final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];

    // Check if the answer is equivalent but unsimplified fraction/expression
    bool isUnsimplified = false;
    if (q['type'] == 'SHORT_ANSWER' &&
        selected.isNotEmpty &&
        correctAnswers.isNotEmpty) {
      final answerStr = selected.first;
      isUnsimplified = correctAnswers.any(
        (c) => _isUnsimplifiedFraction(answerStr, c.toString()),
      );
    } else if ((q['type'] == 'MATRIX_INPUT' || q['type'] == 'EQUATION') &&
        selected.length == correctAnswers.length) {
      for (int i = 0; i < selected.length; i++) {
        if (_isUnsimplifiedFraction(
          selected[i],
          correctAnswers[i].toString(),
        )) {
          isUnsimplified = true;
          break;
        }
      }
    }

    if (isUnsimplified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.lightbulb_outline_rounded, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Almost there! Please simplify your answer.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.indigo,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
      return;
    }

    if (q['type'] == 'SHORT_ANSWER') {
      final answerStr = selected.first;
      correct = correctAnswers.any(
        (c) => _areAnswersEquivalent(c.toString(), answerStr),
      );
    } else if (q['type'] == 'MCQ_SINGLE') {
      if (correctAnswers.isNotEmpty) {
        correct = selected.first == correctAnswers.first.toString();
      }
    } else if (q['type'] == 'MCQ_MULTI') {
      // Check if all correct answers are selected and no incorrect ones
      final correctSet = correctAnswers.map((e) => e.toString()).toSet();
      final selectedSet = selected.toSet();
      correct =
          correctSet.length == selectedSet.length &&
          correctSet.difference(selectedSet).isEmpty;
    } else if (q['type'] == 'ORDERING' || q['type'] == 'MATCHING') {
      if (selected.length == correctAnswers.length) {
        correct = true;
        for (int i = 0; i < selected.length; i++) {
          if (selected[i] != correctAnswers[i].toString()) {
            correct = false;
            break;
          }
        }
      }
    } else if (q['type'] == 'GEOMETRIC') {
      final correctSet = correctAnswers.map((e) => e.toString()).toSet();
      final selectedSet = selected.toSet();
      correct =
          correctSet.length == selectedSet.length &&
          correctSet.difference(selectedSet).isEmpty;
    } else if (q['type'] == 'MATRIX_MCQ') {
      if (selected.length == correctAnswers.length) {
        correct = true;
        for (int i = 0; i < selected.length; i++) {
          if (selected[i] != correctAnswers[i].toString()) {
            correct = false;
            break;
          }
        }
      }
    } else if (q['type'] == 'MATRIX_INPUT' ||
        q['type'] == 'EQUATION' ||
        q['type'] == 'STATEMENT_DROPDOWN' ||
        q['type'] == 'INLINE_SELECT' ||
        q['type'] == 'FILL_IN_BLANKS') {
      if (selected.length == correctAnswers.length) {
        correct = true;
        for (int i = 0; i < selected.length; i++) {
          if (!_areAnswersEquivalent(
            selected[i],
            correctAnswers[i].toString(),
          )) {
            correct = false;
            break;
          }
        }
      }
    } else if (q['type'] == 'DESCRIPTIVE') {
      final List<dynamic> currentAns = _selectedAnswers[_currentQuestionIndex] ?? ["", "", ""];
      final String typedText = currentAns.isNotEmpty ? currentAns[0].toString() : "";
      final String imgUrl = currentAns.length > 1 ? currentAns[1].toString() : "";
      final String presetAns = (q['correctAnswers'] is List && (q['correctAnswers'] as List).isNotEmpty)
          ? q['correctAnswers'][0].toString()
          : (q['explanation'] ?? '');
      final int maxMarks = (q['marks'] as num? ?? 10).toInt();

      final Map<String, dynamic> aiResult = await DeepseekService.evaluateDescriptiveAnswer(
        questionPrompt: q['text'] ?? '',
        presetAnswer: presetAns,
        studentAnswerText: typedText,
        imageUrl: imgUrl,
        maxMarks: maxMarks,
      );

      final bool isPassed = aiResult['isCorrect'] == true;
      final num awardedScore = aiResult['score'] as num? ?? (isPassed ? maxMarks : 0);

      setState(() {
        while (_selectedAnswers[_currentQuestionIndex]!.length < 3) {
          _selectedAnswers[_currentQuestionIndex]!.add("");
        }
        _selectedAnswers[_currentQuestionIndex]![2] = jsonEncode(aiResult);
        _questionFeedback[_currentQuestionIndex] = isPassed;
        _hasSubmittedCurrentQuestion = true;
        if (isPassed) {
          _score += awardedScore.toInt();
          final random = Random();
          _selectedCelebrationLottie =
              _celebrationLotties[random.nextInt(_celebrationLotties.length)];
        }
      });
      _saveProgress();
      return;
    }

    setState(() {
      _questionFeedback[_currentQuestionIndex] = correct;
      _hasSubmittedCurrentQuestion = true;
      if (correct) {
        _score += (q['marks'] as num? ?? 1).toInt();
        final random = Random();
        _selectedCelebrationLottie =
            _celebrationLotties[random.nextInt(_celebrationLotties.length)];
      }
    });
    _saveProgress();

    _showFeedbackDialog(correct);
  }

  void _showFeedbackDialog(bool isCorrect) {
    if (isCorrect) {
      _playCorrectSound();
    } else {
      _playWrongSound();
    }

    final q = _questions[_currentQuestionIndex];
    final bool isLast = _currentQuestionIndex == _questions.length - 1;

    String explanation = '';
    if (!isCorrect) {
      final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];
      if (q['type'] == 'SHORT_ANSWER') {
        explanation = 'Correct answer: ${correctAnswers.first}';
      } else if (q['type'] == 'MCQ_SINGLE') {
        final List<dynamic> options = q['options'] ?? [];
        final int idx = int.tryParse(correctAnswers.first.toString()) ?? -1;
        if (idx >= 0 && idx < options.length) {
          explanation = 'Correct answer: ${options[idx]['text']}';
        }
      } else if (q['type'] == 'MCQ_MULTI') {
        final List<dynamic> options = q['options'] ?? [];
        final List<String> correctTexts = [];
        for (var c in correctAnswers) {
          final int idx = int.tryParse(c.toString()) ?? -1;
          if (idx >= 0 && idx < options.length) {
            correctTexts.add(options[idx]['text']);
          }
        }
        explanation = 'Correct answers: ${correctTexts.join(", ")}';
      } else if (q['type'] == 'MATRIX_INPUT' ||
          q['type'] == 'STATEMENT_DROPDOWN') {
        explanation = 'Correct values: ${correctAnswers.join(", ")}';
      } else if (q['type'] == 'ORDERING') {
        final List<dynamic> options = q['options'] ?? [];
        final List<String> texts = [];
        for (var c in correctAnswers) {
          final idx = int.tryParse(c.toString());
          if (idx != null && idx < options.length) {
            final oText = options[idx]['text'] ?? '';
            texts.add(oText.isNotEmpty ? oText : 'Item ${idx + 1}');
          }
        }
        explanation = 'Correct sequence: ${texts.join(" ➔ ")}';
      } else if (q['type'] == 'MATCHING') {
        explanation = 'Pairs matched correctly!';
      } else if (q['type'] == 'GEOMETRIC') {
        explanation = 'Connections drawn correctly!';
      }
    }

    // showDialog(
    //   context: context,
    //   barrierDismissible: false,
    //   builder: (BuildContext context) {
    //     return Dialog(
    //       backgroundColor: Colors.transparent,
    //       insetPadding: const EdgeInsets.symmetric(horizontal: 24),
    //       child: Container(
    //         padding: const EdgeInsets.all(28),
    //         decoration: BoxDecoration(
    //           color: context.isDark ? const Color(0xFF0F172A) : Colors.white,
    //           borderRadius: BorderRadius.circular(24),
    //           border: Border.all(
    //             color: isCorrect
    //                 ? const Color(0xFF10B981).withOpacity(0.3)
    //                 : const Color(0xFFEF4444).withOpacity(0.3),
    //             width: 1.5,
    //           ),
    //           boxShadow: [
    //             BoxShadow(
    //               color: (isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withOpacity(0.12),
    //               blurRadius: 24,
    //               offset: const Offset(0, 8),
    //             )
    //           ],
    //         ),
    //         child: Column(
    //           mainAxisSize: MainAxisSize.min,
    //           children: [
    //             Container(
    //               padding: const EdgeInsets.all(16),
    //               decoration: BoxDecoration(
    //                 color: (isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withOpacity(0.1),
    //                 shape: BoxShape.circle,
    //               ),
    //               child: Icon(
    //                 isCorrect ? Icons.check_circle : Icons.cancel,
    //                 color: isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444),
    //                 size: 64,
    //               ),
    //             ),
    //             const SizedBox(height: 24),
    //             Text(
    //               isCorrect ? 'Excellent!' : 'Wrong Answer',
    //               style: TextStyle(
    //                 color: isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444),
    //                 fontWeight: FontWeight.w900,
    //                 fontSize: 26,
    //                 letterSpacing: 0.5,
    //               ),
    //             ),
    //             const SizedBox(height: 12),
    //             Text(
    //               isCorrect
    //                   ? 'Great job! You answered this question correctly.'
    //                   : 'Don\'t worry, keep learning and practicing!',
    //               textAlign: TextAlign.center,
    //               style: TextStyle(
    //                 color: context.textColor70,
    //                 fontSize: 14,
    //                 height: 1.4,
    //               ),
    //             ),
    //             if (explanation.isNotEmpty) ...[
    //               const SizedBox(height: 16),
    //               Container(
    //                 padding: const EdgeInsets.all(12),
    //                 decoration: BoxDecoration(
    //                   color: context.glassBg,
    //                   borderRadius: BorderRadius.circular(12),
    //                   border: Border.all(color: context.glassBorder),
    //                 ),
    //                 child: Text(
    //                   explanation,
    //                   textAlign: TextAlign.center,
    //                   style: const TextStyle(
    //                     color: Color(0xFF94A3B8),
    //                     fontSize: 13,
    //                     fontWeight: FontWeight.w600,
    //                   ),
    //                 ),
    //               ),
    //             ],
    //             const SizedBox(height: 28),
    //             SizedBox(
    //               width: double.infinity,
    //               child: ElevatedButton(
    //                 onPressed: () {
    //                   Navigator.pop(context);
    //                   _nextQuestion();
    //                 },
    //                 style: ElevatedButton.styleFrom(
    //                   backgroundColor: isCorrect ? const Color(0xFF10B981) : const Color(0xFF6366F1),
    //                   foregroundColor: Colors.white,
    //                   padding: const EdgeInsets.symmetric(vertical: 14),
    //                   shape: RoundedRectangleBorder(
    //                     borderRadius: BorderRadius.circular(14),
    //                   ),
    //                   elevation: 4,
    //                 ),
    //                 child: Text(
    //                   isLast ? 'View Final Score' : 'Next Question',
    //                   style: const TextStyle(
    //                     fontSize: 15,
    //                     fontWeight: FontWeight.bold,
    //                   ),
    //                 ),
    //               ),
    //             ),
    //           ],
    //         ),
    //       ),
    //     );
    //   },
    // );
  }

  // Next Question or Finish Test
  Future<void> _nextQuestion() async {
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _hasSubmittedCurrentQuestion = false;
        _loadQuestion(_currentQuestionIndex);
      });
      _saveProgress();
    } else {
      // Submit results to backend and finish
      await _finalizeAssessment();
    }
  }

  // Save to SharedPref & backend DB, transition to score screen
  Future<void> _finalizeAssessment() async {
    if (widget.assignmentId != null) {
      setState(() => _isLoading = true);
      try {
        final res = await ApiService.completeAssignment(
          widget.assignmentId!,
          score: _score,
          totalQuestions: _questions.length,
        );
        if (res.statusCode == 200) {
          widget.onCompleted?.call();
        }
      } catch (e) {
        debugPrint('Error saving assignment score: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      setState(() {
        _currentPhase = 3;
      });
      return;
    }

    if (widget.trySingleQuestion != null ||
        (widget.practiceQuestions != null && widget.assignmentId == null)) {
      setState(() {
        _currentPhase = 3;
      });
      return;
    }
    setState(() => _isLoading = true);

    // Prepare answers JSON body
    final List<Map<String, dynamic>> answersJson = [];
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      answersJson.add({
        'questionId': q['_id'],
        'selectedAnswers': _selectedAnswers[i] ?? [],
        'isCorrect': _questionFeedback[i] ?? false,
      });
    }

    final reqBody = {
      'name': _nameCtrl.text.trim(),
      'whatsappNumber': _whatsappCtrl.text.trim(),
      'grade': _selectedGrade,
      'score': _score,
      'totalQuestions': _questions.length,
      'answers': answersJson,
    };

    try {
      final res = await ApiService.post(
        '/assessment-submissions/submit',
        reqBody,
      );
      if (res.statusCode == 201) {
        // Save to Shared Preferences that test has been completed
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_assessment_test_completed', true);
        await _clearSavedProgress();

        setState(() {
          _currentPhase = 3; // Show results screen
        });
      } else {
        final errData = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errData['message'] ??
                  'Failed to submit test results. Please check connection.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Network error saving results. Attempting client-side override...',
          ),
          backgroundColor: Colors.amber,
        ),
      );
      // Force completion locally even if network fails saving, so user isn't stuck
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_assessment_test_completed', true);
      await _clearSavedProgress();
      setState(() {
        _currentPhase = 3;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Launch WhatsApp with summary message
  Future<void> _sendWhatsAppMessage() async {
    final name = _nameCtrl.text.trim();
    final number = _whatsappCtrl.text.trim();
    final msg =
        'Hello $name!\n\nI have successfully completed my Jyamiti Assessment Test for Grade $_selectedGrade.\n\nMy Score: $_score / ${_questions.length} (${((_score / _questions.length) * 100).toStringAsFixed(1)}%)\n\nThank you!';

    // Format whatsapp launch URL
    String cleanNumber = number.replaceAll('+', '').replaceAll(' ', '').trim();
    // Default country prefix if local is provided (assuming standard 10 digit local format if no prefix)
    if (cleanNumber.length == 10 && !cleanNumber.startsWith('91')) {
      cleanNumber =
          '91$cleanNumber'; // default to Indian prefix if 10 digit, user can adjust
    }

    final url = Uri.parse(
      'https://wa.me/$cleanNumber?text=${Uri.encodeComponent(msg)}',
    );
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp app.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open WhatsApp URL.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          widget.trySingleQuestion != null ||
          widget.practiceQuestions != null ||
          _currentPhase != 2,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot go back during the assessment test.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Background Gradient matching login screen
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: context.isDark
                      ? const [
                          Color(0xFF0F172A),
                          Color(0xFF1E1B4B),
                          Color(0xFF080710),
                        ]
                      : const [
                          Color(0xFFF1F5F9),
                          Color(0xFFE2E8F0),
                          Color(0xFFF1F5F9),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

            // Background ambient glowing circles
            Positioned(
              top: -100,
              right: -50,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(
                      0xFF6366F1,
                    ).withOpacity(context.isDark ? 0.08 : 0.05),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -50,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(
                      0xFF8B5CF6,
                    ).withOpacity(context.isDark ? 0.08 : 0.05),
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Center(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: _currentPhase == 2
                        ? (MediaQuery.of(context).size.width > 900
                              ? 1450.0
                              : 700.0)
                        : _currentPhase == 3
                        ? 650.0
                        : 500.0,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 16.0,
                  ),
                  child: _buildPhaseContent(),
                ),
              ),
            ),

            if (_currentPhase == 2 && _showWritingPad && _isWritingPadFullScreen)
              Positioned.fill(
                child: Container(
                  color: context.isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFFCFDFE),
                  child: WritingPadWidget(
                    key: _writingPadKey,
                    questionText: _questions.isNotEmpty &&
                            _currentQuestionIndex < _questions.length
                        ? _extractQuestionText(_questions[_currentQuestionIndex])
                        : '',
                    isFullScreen: true,
                    onToggleFullScreen: () {
                      setState(() {
                        _isWritingPadFullScreen = false;
                      });
                    },
                    onClose: () {
                      setState(() {
                        _showWritingPad = false;
                        _isWritingPadFullScreen = false;
                      });
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Build screen based on Phase
  Widget _buildPhaseContent() {
    switch (_currentPhase) {
      case 1:
        return _buildRegistrationForm();
      case 2:
        return _buildTestScreen();
      case 3:
        return _buildResultsScreen();
      default:
        return const Center(
          child: JyamitiLoader(color: Color(0xFF6366F1)),
        );
    }
  }

  // PHASE 1: Registration & Welcome Form
  Widget _buildRegistrationForm() {
    final isDark = context.isDark;
    return SingleChildScrollView(
      child:
          Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withOpacity(0.4)
                          : const Color(0xFF4F46E5).withOpacity(0.08),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.all(32.0),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.03)
                            : Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDark
                              ? context.textColor.withOpacity(0.08)
                              : const Color(0xFF8B5CF6).withOpacity(0.15),
                          width: 1.5,
                        ),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(
                                    0xFF6366F1,
                                  ).withOpacity(0.1),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF6366F1,
                                    ).withOpacity(0.3),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.assignment_turned_in_rounded,
                                  size: 48,
                                  color: Color(0xFF818CF8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Assessment Test',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: context.textColor,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Please fill in your details to start the assessment. This helps us customize your learning path.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: context.textColor.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Name Input
                            TextFormField(
                              controller: _nameCtrl,
                              style: TextStyle(color: context.textColor),
                              decoration: InputDecoration(
                                labelText: 'Full Name',
                                labelStyle: TextStyle(
                                  color: context.textColor.withOpacity(0.5),
                                ),
                                prefixIcon: Icon(
                                  Icons.person_outline_rounded,
                                  color: context.textColor.withOpacity(0.5),
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? context.textColor.withOpacity(0.02)
                                    : const Color(0xFFF8FAFC),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? context.textColor.withOpacity(0.08)
                                        : const Color(0xFFE2E8F0),
                                    width: 1.0,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF6366F1),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Please enter your name'
                                  : null,
                            ),
                            const SizedBox(height: 20),

                            // WhatsApp Number Input
                            TextFormField(
                              controller: _whatsappCtrl,
                              keyboardType: TextInputType.phone,
                              style: TextStyle(color: context.textColor),
                              decoration: InputDecoration(
                                labelText: 'WhatsApp Number',
                                labelStyle: TextStyle(
                                  color: context.textColor.withOpacity(0.5),
                                ),
                                prefixIcon: Icon(
                                  Icons.phone_android_rounded,
                                  color: context.textColor.withOpacity(0.5),
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? context.textColor.withOpacity(0.02)
                                    : const Color(0xFFF8FAFC),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? context.textColor.withOpacity(0.08)
                                        : const Color(0xFFE2E8F0),
                                    width: 1.0,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF6366F1),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Please enter your WhatsApp number';
                                }
                                if (v.trim().length < 8) {
                                  return 'Please enter a valid phone number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            // Grade Selector
                            DropdownButtonFormField<int>(
                              value: _selectedGrade,
                              dropdownColor: isDark
                                  ? const Color(0xFF1E1B4B)
                                  : Colors.white,
                              style: TextStyle(color: context.textColor),
                              decoration: InputDecoration(
                                labelText: 'Select Your Grade',
                                labelStyle: TextStyle(
                                  color: context.textColor.withOpacity(0.5),
                                ),
                                prefixIcon: Icon(
                                  Icons.school_outlined,
                                  color: context.textColor.withOpacity(0.5),
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? context.textColor.withOpacity(0.02)
                                    : const Color(0xFFF8FAFC),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? context.textColor.withOpacity(0.08)
                                        : const Color(0xFFE2E8F0),
                                    width: 1.0,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF6366F1),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              items: List.generate(12, (index) {
                                final grade = index + 1;
                                return DropdownMenuItem<int>(
                                  value: grade,
                                  child: Text(
                                    'Grade $grade',
                                    style: TextStyle(color: context.textColor),
                                  ),
                                );
                              }),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedGrade = val);
                                }
                              },
                            ),
                            const SizedBox(height: 24),

                            // Error message
                            if (_errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.redAccent.withOpacity(0.2),
                                  ),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ).animate().shake(duration: 400.ms),
                              const SizedBox(height: 24),
                            ],

                            // Action buttons
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isCheckingPhone
                                        ? null
                                        : () => Navigator.pop(context),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: isDark
                                          ? Colors.white70
                                          : const Color(0xFF475569),
                                      side: BorderSide(
                                        color: isDark
                                            ? context.glassBorder
                                            : const Color(0xFFCBD5E1),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text('Back'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF4F46E5),
                                          Color(0xFF6366F1),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF6366F1,
                                          ).withOpacity(isDark ? 0.3 : 0.15),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: _isCheckingPhone
                                          ? null
                                          : _startTest,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: _isCheckingPhone
                                          ? SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: JyamitiLoader(
                                                color: context.textColor,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text(
                                              'Start Test',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 500.ms)
              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
    );
  }

  String _extractQuestionText(dynamic q) {
    if (q == null) return '';
    if (q is String) return q;
    if (q is Map) {
      for (final key in [
        'descriptiveText',
        'questionText',
        'question',
        'title',
        'prompt',
        'text',
        'problem',
        'statement',
        'content',
        'stem',
        'qText',
        'q_text'
      ]) {
        if (q.containsKey(key) && q[key] != null && q[key].toString().trim().isNotEmpty) {
          return q[key].toString().trim();
        }
      }
    }
    try {
      final dynamic obj = q;
      final text = (obj.questionText ?? obj.question ?? obj.title ?? obj.descriptiveText ?? obj.text ?? '').toString();
      if (text.trim().isNotEmpty) return text.trim();
    } catch (_) {}

    return '';
  }

  bool _isQuestionClasswork(dynamic q) {
    if (q == null) return false;

    bool parseBool(dynamic val) {
      if (val == null) return false;
      if (val is bool) return val;
      if (val is num) return val != 0;
      final str = val.toString().toLowerCase().trim();
      return str == 'true' || str == '1' || str == 'yes';
    }

    if (parseBool(q['isClasswork']) ||
        parseBool(q['forTutorOnly']) ||
        parseBool(q['isTutorOnly'])) {
      return true;
    }
    final cat = (q['category'] ?? q['tag'] ?? q['targetAudience'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (cat == 'classwork' ||
        cat == 'tutor' ||
        cat == 'tutor_only' ||
        cat == 'tutoronly' ||
        cat == 'teacher') {
      return true;
    }
    return false;
  }

  // PHASE 2: Live Test Screen
  Widget _buildTestScreen() {
    if (_questions.isEmpty) return const SizedBox();

    final bool isPracticeMode =
        widget.practiceQuestions != null || widget.trySingleQuestion != null;

    // Filter questions based on Mode when in Practice Mode
    List<dynamic> effectiveQuestions = _questions;
    if (isPracticeMode) {
      if (_practiceViewMode == 'TUTOR') {
        effectiveQuestions =
            _questions.where((q) => _isQuestionClasswork(q)).toList();
      } else if (_practiceViewMode == 'STUDENT') {
        effectiveQuestions =
            _questions.where((q) => !_isQuestionClasswork(q)).toList();
      }
    }

    if (effectiveQuestions.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _practiceViewMode == 'TUTOR'
                    ? Icons.cast_for_education_rounded
                    : Icons.school_rounded,
                color: const Color(0xFF6366F1),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _practiceViewMode == 'TUTOR'
                    ? 'No Tutor Only (Classwork) Questions'
                    : 'No Student Practice Questions',
                style: GoogleFonts.spaceGrotesk(
                  color: context.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _practiceViewMode == 'TUTOR'
                    ? 'There are no questions flagged for Tutor Classwork in this practice set.'
                    : 'There are no questions flagged for Student Practice in this practice set.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textColor60, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _practiceViewMode =
                            _practiceViewMode == 'TUTOR' ? 'STUDENT' : 'TUTOR';
                        _currentQuestionIndex = 0;
                      });
                    },
                    icon: Icon(
                      _practiceViewMode == 'TUTOR'
                          ? Icons.school_rounded
                          : Icons.cast_for_education_rounded,
                    ),
                    label: Text(
                      _practiceViewMode == 'TUTOR'
                          ? 'Switch to Student Mode'
                          : 'Switch to Tutor Mode',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Exit'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final int currIdx = _currentQuestionIndex < effectiveQuestions.length
        ? _currentQuestionIndex
        : 0;
    final q = effectiveQuestions[currIdx];
    final selected = _selectedAnswers[currIdx] ?? [];
    final questionNo = currIdx + 1;
    final total = effectiveQuestions.length;
    final progress = questionNo / total;
    final isBigScreen = MediaQuery.of(context).size.width > 900;

    final Widget questionView = Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progress header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isPracticeMode)
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: context.textColor,
                        ),
                        tooltip: 'Back to practice list',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Question $questionNo of $total',
                        style: GoogleFonts.spaceGrotesk(
                          color: context.textColor70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Question $questionNo of $total',
                    style: GoogleFonts.spaceGrotesk(
                      color: context.textColor70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                if (isPracticeMode)
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: context.isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.glassBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _practiceViewMode = 'STUDENT';
                              _currentQuestionIndex = 0;
                            });
                          },
                          borderRadius: BorderRadius.circular(7),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _practiceViewMode == 'STUDENT'
                                  ? const Color(0xFF6366F1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.school_rounded,
                                  size: 14,
                                  color: _practiceViewMode == 'STUDENT'
                                      ? Colors.white
                                      : context.textColor60,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Student Mode',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _practiceViewMode == 'STUDENT'
                                        ? Colors.white
                                        : context.textColor60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _practiceViewMode = 'TUTOR';
                              _currentQuestionIndex = 0;
                            });
                          },
                          borderRadius: BorderRadius.circular(7),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _practiceViewMode == 'TUTOR'
                                  ? const Color(0xFF10B981)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.cast_for_education_rounded,
                                  size: 14,
                                  color: _practiceViewMode == 'TUTOR'
                                      ? Colors.white
                                      : context.textColor60,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Tutor Mode (Classwork)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _practiceViewMode == 'TUTOR'
                                        ? Colors.white
                                        : context.textColor60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        if (isBigScreen) {
                          setState(() {
                            _showWritingPad = !_showWritingPad;
                          });
                        } else {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => Container(
                              height: MediaQuery.of(context).size.height * 0.85,
                              margin: const EdgeInsets.all(12),
                              child: WritingPadWidget(
                                isInline: false,
                                questionText: _extractQuestionText(q),
                                onClose: () => Navigator.pop(context),
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(
                        Icons.draw_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: Text(
                        isBigScreen
                            ? (_showWritingPad
                                  ? 'Hide Writing Screen'
                                  : 'Writing Screen')
                            : 'Writing Pad',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (widget.trySingleQuestion == null)
                      Text(
                        'Score: $_score',
                        style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFF34D399),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: context.glassBorder,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF6366F1),
                ),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 18),

            // Main Question Box
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: context.isDark
                                ? Colors.black.withOpacity(0.3)
                                : const Color(0xFF4F46E5).withOpacity(0.04),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: context.isDark
                                  ? Colors.white.withOpacity(0.03)
                                  : Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: context.isDark
                                    ? context.textColor.withOpacity(0.08)
                                    : const Color(0xFF8B5CF6).withOpacity(0.15),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Descriptive text (above the image if present)
                                if (q['descriptiveText'] != null &&
                                    q['descriptiveText']
                                        .toString()
                                        .trim()
                                        .isNotEmpty) ...[
                                  LatexRichText(
                                    text: q['descriptiveText']
                                        .toString()
                                        .trim(),
                                    style: GoogleFonts.outfit(
                                      color: context.textColor.withOpacity(0.9),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                // Render geometric canvas or question image
                                if (q['type'] == 'GEOMETRIC') ...[
                                  _buildAnswerInputs(q, selected),
                                  const SizedBox(height: 16),
                                ] else if (q['questionImage'] != null &&
                                    q['questionImage']
                                        .toString()
                                        .isNotEmpty) ...[
                                  Center(
                                    child: GestureDetector(
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => Dialog(
                                            backgroundColor: Colors.transparent,
                                            insetPadding: const EdgeInsets.all(
                                              16,
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Align(
                                                  alignment: Alignment.topRight,
                                                  child: IconButton(
                                                    icon: Icon(
                                                      Icons.close,
                                                      color: context.textColor,
                                                      size: 28,
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Container(
                                                  decoration: BoxDecoration(
                                                    color: context.isDark
                                                        ? const Color(
                                                            0xFF1E293B,
                                                          )
                                                        : Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    border: Border.all(
                                                      color:
                                                          context.glassBorder,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.5),
                                                        blurRadius: 20,
                                                        offset: const Offset(
                                                          0,
                                                          10,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          15,
                                                        ),
                                                    child: InteractiveViewer(
                                                      minScale: 1.0,
                                                      maxScale: 4.0,
                                                      child: SvgLabelOverlay(
                                                        imagePath:
                                                            q['questionImage'],
                                                        isSvg:
                                                            q['isSvg'] == true,
                                                        labels:
                                                            q['svgLabels'] ??
                                                            [],
                                                        aspectRatio: 4 / 3,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  'Pinch to zoom / Drag to pan',
                                                  style: TextStyle(
                                                    color: context.textColor54,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Stack(
                                          alignment: Alignment.bottomRight,
                                          children: [
                                            SvgLabelOverlay(
                                              imagePath: q['questionImage'],
                                              isSvg: q['isSvg'] == true,
                                              labels: q['svgLabels'] ?? [],
                                              height: 180,
                                            ),
                                            Container(
                                              margin: const EdgeInsets.all(8),
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Icon(
                                                Icons.zoom_in,
                                                color: context.textColor70,
                                                size: 18,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                // Question text (below the image, extra bold)
                                if (q['type'] != 'INLINE_SELECT')
                                  LatexRichText(
                                    text: q['text'],
                                    style: GoogleFonts.outfit(
                                      color: context.textColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Answers Section
                    if (q['type'] != 'INLINE_SELECT' &&
                        q['type'] != 'GEOMETRIC') ...[
                      Text(
                        q['type'] == 'MCQ_MULTI'
                            ? 'Select all correct answers:'
                            : q['type'] == 'SHORT_ANSWER'
                            ? 'Write your answer:'
                            : q['type'] == 'STATEMENT_DROPDOWN'
                            ? 'Select correct statements:'
                            : 'Choose one answer:',
                        style: TextStyle(
                          color: context.textColor54,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (q['type'] != 'GEOMETRIC')
                      _buildAnswerInputs(q, selected),
                  ],
                ),
              ),
            ),

            if (_hasSubmittedCurrentQuestion) ...[
              const SizedBox(height: 12),
              _buildFeedbackBanner(q),
            ],

            const SizedBox(height: 16),

            // Submit/Next Actions Footer
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _hasSubmittedCurrentQuestion
                  ? Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                        ),
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _nextQuestion,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: JyamitiLoader(
                                  color: context.textColor,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _currentQuestionIndex == total - 1
                                    ? 'Finish Assessment'
                                    : 'Next Question',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _submitAnswer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 5,
                      ),
                      child: const Text(
                        'Submit Answer',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
            ),
          ],
        ).animate().fadeIn(duration: 400.ms),
        if (_hasSubmittedCurrentQuestion &&
            (_questionFeedback[_currentQuestionIndex] ?? false))
          Positioned(
            key: ValueKey('celebration_${_currentQuestionIndex}'),
            bottom: 60,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Animate(
                effects: [
                  FadeEffect(duration: 300.ms),
                  ThenEffect(delay: 2200.ms),
                  FadeEffect(begin: 1.0, end: 0.0, duration: 800.ms),
                ],
                child: Center(
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: Lottie.asset(
                      _selectedCelebrationLottie,
                      fit: BoxFit.contain,
                      repeat: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (isBigScreen && _showWritingPad) {
      final String currentQText = _extractQuestionText(q);

      if (_isWritingPadFullScreen) {
        return questionView;
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 1, child: questionView),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: WritingPadWidget(
              key: _writingPadKey,
              questionText: currentQText,
              isFullScreen: false,
              onToggleFullScreen: () {
                setState(() {
                  _isWritingPadFullScreen = true;
                });
              },
              onClose: () {
                setState(() {
                  _showWritingPad = false;
                });
              },
            ),
          ),
        ],
      );
    }

    return questionView;
  }

  // PHASE 3: Assessment Results/Finish Screen
  Widget _buildResultsScreen() {
    final totalQuestions = _questions.length;
    final pct = totalQuestions > 0 ? (_score / totalQuestions) * 100 : 0.0;
    final isDark = context.isDark;

    // Choose result feedback text and color
    String feedbackTitle = 'Good Effort!';
    String feedbackDesc =
        'Keep learning and practicing. You are on the right path!';
    Color accentColor = const Color(0xFFF59E0B); // Amber
    IconData icon = Icons.star_half_rounded;

    if (pct >= 80) {
      feedbackTitle = 'Outstanding!';
      feedbackDesc =
          'Exceptional performance! You have mastered these geometry concepts!';
      accentColor = const Color(0xFF10B981); // Emerald
      icon = Icons.emoji_events_rounded;
    } else if (pct >= 50) {
      feedbackTitle = 'Well Done!';
      feedbackDesc =
          'Great job! You have a solid baseline. Practice will make you perfect!';
      accentColor = const Color(0xFF6366F1); // Indigo
      icon = Icons.thumb_up_alt_rounded;
    }

    return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withOpacity(0.4)
                    : const Color(0xFF4F46E5).withOpacity(0.08),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(32.0),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.03)
                      : Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? context.textColor.withOpacity(0.08)
                        : const Color(0xFF8B5CF6).withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Icon
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor.withOpacity(0.1),
                          border: Border.all(
                            color: accentColor.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(icon, size: 56, color: accentColor),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Score circle
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 140,
                            height: 140,
                            child: JyamitiLoader(
                              value: totalQuestions > 0
                                  ? _score / totalQuestions
                                  : 0,
                              backgroundColor: isDark
                                  ? context.glassBg
                                  : const Color(0xFFF1F5F9),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                accentColor,
                              ),
                              strokeWidth: 10,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$_score/$totalQuestions',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: context.textColor,
                                ),
                              ),
                              Text(
                                '${pct.toStringAsFixed(0)}%',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  color: context.textColor60,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    Text(
                      feedbackTitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: context.textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      feedbackDesc,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: context.textColor54,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Share to WhatsApp
                    if (widget.trySingleQuestion == null) ...[
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF25D366).withOpacity(0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _sendWhatsAppMessage,
                          icon: const Icon(Icons.share, color: Colors.white),
                          label: const Text(
                            'Send to WhatsApp',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Return / Close
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark
                            ? Colors.white70
                            : const Color(0xFF475569),
                        side: BorderSide(
                          color: isDark
                              ? context.glassBorder
                              : const Color(0xFFCBD5E1),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Close & Continue'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 500.ms)
        .scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOutBack);
  }

  // Answer selection widget based on Question type
  Widget _buildAnswerInputs(dynamic q, List<String> selected) {
    if (q['type'] == 'INLINE_SELECT') {
      final bool showResult = _hasSubmittedCurrentQuestion;
      final String text = q['text'] ?? '';
      final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];
      final List<dynamic> currentSelection =
          _selectedAnswers[_currentQuestionIndex] ?? [];

      int globalSelectIdx = 0;
      final regExp = RegExp(r'\[SELECT:(.*?):(.*?)\]');

      final List<Widget> lineWidgets = [];
      int currentOffset = 0;
      final Iterable<Match> matches = regExp.allMatches(text);

      for (var m in matches) {
        final String beforeText = text.substring(currentOffset, m.start);
        if (beforeText.isNotEmpty) {
          lineWidgets.add(
            LatexRichText(
              text: beforeText,
              style: GoogleFonts.spaceGrotesk(
                color: context.textColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }

        final int selectIdx = globalSelectIdx++;
        while (currentSelection.length <= selectIdx) {
          currentSelection.add("");
        }
        final String currentValue = currentSelection[selectIdx];

        final String tagChoicesRaw = m.group(1) ?? '';
        final List<String> choices = tagChoicesRaw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        final bool isCorrect =
            (selectIdx < correctAnswers.length) &&
            _areAnswersEquivalent(
              currentValue,
              correctAnswers[selectIdx].toString(),
            );

        lineWidgets.add(
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            height: 38,
            decoration: BoxDecoration(
              color: showResult
                  ? (isCorrect
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1))
                  : (context.isDark ? context.glassBg : Colors.white),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: showResult
                    ? (isCorrect ? Colors.green : Colors.redAccent)
                    : (context.isDark
                          ? const Color(0xFF6366F1).withOpacity(0.4)
                          : const Color(0xFFCBD5E1)),
                width: showResult ? 1.5 : 1.0,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: currentValue.isEmpty ? null : currentValue,
                hint: Text(
                  'Select...',
                  style: TextStyle(
                    color: context.textColor54.withOpacity(0.5),
                    fontSize: 14,
                  ),
                ),
                dropdownColor: context.isDark
                    ? const Color(0xFF1E293B)
                    : Colors.white,
                icon: Icon(Icons.arrow_drop_down, color: context.textColor70),
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                onChanged: showResult
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() {
                            while (_selectedAnswers[_currentQuestionIndex]!
                                    .length <=
                                selectIdx) {
                              _selectedAnswers[_currentQuestionIndex]!.add("");
                            }
                            _selectedAnswers[_currentQuestionIndex]![selectIdx] =
                                val;
                          });
                          _saveProgress();
                        }
                      },
                items: choices.map((choice) {
                  return DropdownMenuItem<String>(
                    value: choice,
                    child: LatexRichText(
                      text: choice,
                      style: TextStyle(color: context.textColor, fontSize: 14),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );

        currentOffset = m.end;
      }

      final String afterText = text.substring(currentOffset);
      if (afterText.isNotEmpty) {
        lineWidgets.add(
          LatexRichText(
            text: afterText,
            style: GoogleFonts.spaceGrotesk(
              color: context.textColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.isDark ? context.glassBg : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.isDark
                ? context.glassBorder
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.start,
          spacing: 4,
          runSpacing: 10,
          children: lineWidgets,
        ),
      );
    }

    if (q['type'] == 'FILL_IN_BLANKS') {
      final bool showResult = _hasSubmittedCurrentQuestion;
      final String text = q['text'] ?? '';
      final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];
      final List<dynamic> currentSelection =
          _selectedAnswers[_currentQuestionIndex] ?? [];

      int globalBlankIdx = 0;
      final regExp = RegExp(r'\[(?:BLANK|INPUT)(?::([^\]]*))?\]', caseSensitive: false);

      final List<Widget> lineWidgets = [];
      int currentOffset = 0;
      final Iterable<Match> matches = regExp.allMatches(text);

      for (var m in matches) {
        final String beforeText = text.substring(currentOffset, m.start);
        if (beforeText.isNotEmpty) {
          lineWidgets.add(
            LatexRichText(
              text: beforeText,
              style: GoogleFonts.spaceGrotesk(
                color: context.textColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }

        final int blankIdx = globalBlankIdx++;
        while (currentSelection.length <= blankIdx) {
          currentSelection.add("");
        }
        final String currentValue = currentSelection[blankIdx];

        String expectedAnswer = (m.group(1) ?? '').trim();
        if (expectedAnswer.isEmpty && blankIdx < correctAnswers.length) {
          expectedAnswer = correctAnswers[blankIdx].toString().trim();
        }

        final bool isCorrect = _areAnswersEquivalent(currentValue, expectedAnswer);

        lineWidgets.add(
          Container(
            width: 140,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            height: 40,
            decoration: BoxDecoration(
              color: showResult
                  ? (isCorrect
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1))
                  : (context.isDark ? context.glassBg : Colors.white),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: showResult
                    ? (isCorrect ? Colors.green : Colors.redAccent)
                    : (context.isDark
                          ? const Color(0xFF6366F1).withOpacity(0.4)
                          : const Color(0xFFCBD5E1)),
                width: showResult ? 1.5 : 1.0,
              ),
            ),
            child: TextField(
              enabled: !showResult,
              controller: TextEditingController(text: currentValue)
                ..selection = TextSelection.collapsed(offset: currentValue.length),
              style: GoogleFonts.spaceGrotesk(
                color: showResult
                    ? (isCorrect ? Colors.green[700] : Colors.red[700])
                    : context.textColor,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: 'fill blank...',
                hintStyle: TextStyle(
                  color: context.textColor54.withOpacity(0.4),
                  fontSize: 13,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (val) {
                while (_selectedAnswers[_currentQuestionIndex]!.length <= blankIdx) {
                  _selectedAnswers[_currentQuestionIndex]!.add("");
                }
                _selectedAnswers[_currentQuestionIndex]![blankIdx] = val.trim();
                _saveProgress();
              },
            ),
          ),
        );

        if (showResult && !isCorrect && expectedAnswer.isNotEmpty) {
          lineWidgets.add(
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '($expectedAnswer)',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }

        currentOffset = m.end;
      }

      final String remainingText = text.substring(currentOffset);
      if (remainingText.isNotEmpty) {
        lineWidgets.add(
          LatexRichText(
            text: remainingText,
            style: GoogleFonts.spaceGrotesk(
              color: context.textColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.isDark ? context.glassBg : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.isDark
                ? context.glassBorder
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.start,
          spacing: 4,
          runSpacing: 10,
          children: lineWidgets,
        ),
      );
    }

    if (q['type'] == 'DESCRIPTIVE') {
      final bool showResult = _hasSubmittedCurrentQuestion;
      final List<dynamic> currentSelection =
          _selectedAnswers[_currentQuestionIndex] ?? ["", "", ""];
      while (currentSelection.length < 3) {
        currentSelection.add("");
      }
      final String typedText = currentSelection[0].toString();
      final String uploadedImgUrl = currentSelection[1].toString();
      final String aiEvalRaw = currentSelection[2].toString();

      Map<String, dynamic>? aiResult;
      if (aiEvalRaw.isNotEmpty) {
        try {
          aiResult = Map<String, dynamic>.from(jsonDecode(aiEvalRaw));
        } catch (_) {}
      }

      final isDark = context.isDark;

      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.edit_document,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Handwritten / Descriptive Response',
                  style: GoogleFonts.spaceGrotesk(
                    color: context.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Write your solution on paper, snap a picture or pick an image, or use the digital drawing pad. DeepSeek AI will evaluate the semantic meaning of your answer.',
              style: TextStyle(
                color: context.textColor60,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),

            if (uploadedImgUrl.isNotEmpty) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      uploadedImgUrl.startsWith('http')
                          ? uploadedImgUrl
                          : '${ApiService.baseUrl}/$uploadedImgUrl',
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (!showResult)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            currentSelection[1] = "";
                          });
                          _saveProgress();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (!showResult)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.pickFiles(
                          type: FileType.image,
                          withData: true,
                        );
                        if (result != null && result.files.isNotEmpty) {
                          final file = result.files.first;
                          if (file.bytes != null) {
                            final streamedRes = await ApiService.uploadFile(
                              '/assessment-questions/upload',
                              file.bytes!,
                              file.name,
                              fieldName: 'file',
                            );
                            final resBody = await streamedRes.stream.bytesToString();
                            if (streamedRes.statusCode == 200) {
                              final data = jsonDecode(resBody);
                              setState(() {
                                currentSelection[1] = data['fileUrl'] ?? '';
                              });
                              _saveProgress();
                            }
                          }
                        }
                      },
                      icon: const Icon(
                        Icons.cloud_upload_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: Text(
                        uploadedImgUrl.isEmpty
                            ? 'Upload Handwritten Photo'
                            : 'Change Photo',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showWritingPad = true;
                        _isWritingPadFullScreen = true;
                      });
                    },
                    icon: const Icon(
                      Icons.draw_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Open Canvas',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),

            TextFormField(
              enabled: !showResult,
              initialValue: typedText,
              style: TextStyle(color: context.textColor),
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Typed Answer / Solution Steps (Optional)',
                hintText: 'Enter your typed explanation or notes here...',
                labelStyle: TextStyle(color: context.textColor70),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (val) {
                currentSelection[0] = val.trim();
                _saveProgress();
              },
            ),

            if (showResult && aiResult != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF10B981).withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: Color(0xFF10B981),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🤖 Polite AI Evaluation Result',
                                style: GoogleFonts.spaceGrotesk(
                                  color: context.textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                'Score Awarded: ${aiResult['score'] ?? 10} / ${(q['marks'] as num? ?? 10).toInt()} Marks (${aiResult['scorePercentage'] ?? 100}%)',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      aiResult['politeFeedback'] ??
                          'Great job submitting your handwritten answer!',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    if (aiResult['semanticComparison'] != null &&
                        aiResult['semanticComparison'].toString().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '💡 Meaning Match: ${aiResult['semanticComparison']}',
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (q['type'] == 'EQUATION') {
      final bool showResult = _hasSubmittedCurrentQuestion;
      final List<dynamic> steps = q['options'] ?? [];
      final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];
      final List<dynamic> currentSelection =
          _selectedAnswers[_currentQuestionIndex] ?? [];

      int globalInputIdx = 0;
      final regExp = RegExp(r'\[INPUT:(.*?)\]');

      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.isDark ? context.glassBg : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.isDark
                ? context.glassBorder
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(steps.length, (stepIdx) {
            final String stepText = steps[stepIdx]['text'] ?? '';
            final List<Widget> lineWidgets = [];

            int currentOffset = 0;
            final Iterable<Match> matches = regExp.allMatches(stepText);

            for (var m in matches) {
              final String beforeText = stepText.substring(
                currentOffset,
                m.start,
              );
              if (beforeText.isNotEmpty) {
                lineWidgets.add(
                  LatexRichText(
                    text: beforeText,
                    style: GoogleFonts.spaceGrotesk(
                      color: context.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }

              final int inputIdx = globalInputIdx++;
              while (currentSelection.length <= inputIdx) {
                currentSelection.add("");
              }
              final String currentValue = currentSelection[inputIdx];
              final bool isCorrect =
                  (inputIdx < correctAnswers.length) &&
                  (currentValue.trim().toLowerCase() ==
                      correctAnswers[inputIdx].toString().trim().toLowerCase());

              final String stepCorrectAnswer =
                  (inputIdx < correctAnswers.length)
                  ? correctAnswers[inputIdx].toString()
                  : '';
              final bool isInputLatex = _isLatex(stepCorrectAnswer);

              if (isInputLatex) {
                lineWidgets.add(
                  GestureDetector(
                    onTap: showResult
                        ? null
                        : () => _showMathDialog(
                            _currentQuestionIndex,
                            inputIdx: inputIdx,
                          ),
                    child: Container(
                      width: 110,
                      height: 36,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: showResult
                            ? (isCorrect
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.red.withOpacity(0.1))
                            : (context.isDark ? context.glassBg : Colors.white),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: showResult
                              ? (isCorrect ? Colors.green : Colors.redAccent)
                              : (context.isDark
                                    ? const Color(0xFF6366F1).withOpacity(0.4)
                                    : const Color(0xFFCBD5E1)),
                          width: showResult ? 1.5 : 1.0,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: currentValue.isEmpty
                          ? Text(
                              '?',
                              style: TextStyle(
                                color: context.textColor54.withOpacity(0.4),
                                fontSize: 13,
                              ),
                            )
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                ),
                                child: LatexRichText(
                                  text: '\$$currentValue\$',
                                  style: TextStyle(
                                    color: context.textColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                );
              } else {
                lineWidgets.add(
                  Container(
                    width: 85,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: TextFormField(
                      initialValue: currentValue,
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      enabled: !showResult,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        hintText: showResult ? '' : '?',
                        hintStyle: TextStyle(
                          color: context.textColor54.withOpacity(0.4),
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: showResult
                            ? (isCorrect
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.red.withOpacity(0.1))
                            : (context.isDark ? context.glassBg : Colors.white),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: showResult
                                ? (isCorrect ? Colors.green : Colors.redAccent)
                                : (context.isDark
                                      ? context.glassBorder
                                      : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isCorrect ? Colors.green : Colors.redAccent,
                            width: 1.5,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF6366F1),
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {
                          while (_selectedAnswers[_currentQuestionIndex]!
                                  .length <=
                              inputIdx) {
                            _selectedAnswers[_currentQuestionIndex]!.add("");
                          }
                          _selectedAnswers[_currentQuestionIndex]![inputIdx] =
                              val;
                        });
                        _saveProgress();
                      },
                    ),
                  ),
                );
              }

              currentOffset = m.end;
            }

            final String afterText = stepText.substring(currentOffset);
            if (afterText.isNotEmpty) {
              lineWidgets.add(
                LatexRichText(
                  text: afterText,
                  style: GoogleFonts.spaceGrotesk(
                    color: context.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }

            if (lineWidgets.isEmpty) {
              lineWidgets.add(const SizedBox(height: 24));
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.start,
                spacing: 4,
                runSpacing: 8,
                children: lineWidgets,
              ),
            );
          }),
        ),
      );
    }

    if (q['type'] == 'STATEMENT_DROPDOWN') {
      final bool showResult = _hasSubmittedCurrentQuestion;
      final List<dynamic> statements = q['options'] ?? [];
      final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];
      final List<dynamic> currentSelection =
          _selectedAnswers[_currentQuestionIndex] ?? [];

      int globalSelectIdx = 0;
      final regExp = RegExp(r'\[SELECT:(.*?):(.*?)\]');

      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.isDark ? context.glassBg : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.isDark
                ? context.glassBorder
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(statements.length, (stmtIdx) {
            final String stmtText = statements[stmtIdx]['text'] ?? '';
            final List<Widget> lineWidgets = [];

            int currentOffset = 0;
            final Iterable<Match> matches = regExp.allMatches(stmtText);

            for (var m in matches) {
              final String beforeText = stmtText.substring(
                currentOffset,
                m.start,
              );
              if (beforeText.isNotEmpty) {
                lineWidgets.add(
                  LatexRichText(
                    text: beforeText,
                    style: GoogleFonts.spaceGrotesk(
                      color: context.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }

              final int selectIdx = globalSelectIdx++;
              while (currentSelection.length <= selectIdx) {
                currentSelection.add("");
              }
              final String currentValue = currentSelection[selectIdx];

              final String tagChoicesRaw = m.group(1) ?? '';
              final List<String> choices = tagChoicesRaw
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();

              final bool isCorrect =
                  (selectIdx < correctAnswers.length) &&
                  (currentValue.trim().toLowerCase() ==
                      correctAnswers[selectIdx]
                          .toString()
                          .trim()
                          .toLowerCase());

              lineWidgets.add(
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  height: 38,
                  decoration: BoxDecoration(
                    color: showResult
                        ? (isCorrect
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1))
                        : (context.isDark ? context.glassBg : Colors.white),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: showResult
                          ? (isCorrect ? Colors.green : Colors.redAccent)
                          : (context.isDark
                                ? const Color(0xFF6366F1).withOpacity(0.4)
                                : const Color(0xFFCBD5E1)),
                      width: showResult ? 1.5 : 1.0,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: currentValue.isEmpty ? null : currentValue,
                      hint: Text(
                        'Select...',
                        style: TextStyle(
                          color: context.textColor54.withOpacity(0.5),
                          fontSize: 14,
                        ),
                      ),
                      dropdownColor: context.isDark
                          ? const Color(0xFF1E293B)
                          : Colors.white,
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: context.textColor70,
                      ),
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      onChanged: showResult
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() {
                                  while (_selectedAnswers[_currentQuestionIndex]!
                                          .length <=
                                      selectIdx) {
                                    _selectedAnswers[_currentQuestionIndex]!
                                        .add("");
                                  }
                                  _selectedAnswers[_currentQuestionIndex]![selectIdx] =
                                      val;
                                });
                                _saveProgress();
                              }
                            },
                      items: choices.map((choice) {
                        return DropdownMenuItem<String>(
                          value: choice,
                          child: LatexRichText(
                            text: choice,
                            style: TextStyle(
                              color: context.textColor,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              );

              currentOffset = m.end;
            }

            final String afterText = stmtText.substring(currentOffset);
            if (afterText.isNotEmpty) {
              lineWidgets.add(
                LatexRichText(
                  text: afterText,
                  style: GoogleFonts.spaceGrotesk(
                    color: context.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }

            if (lineWidgets.isEmpty) {
              lineWidgets.add(const SizedBox(height: 24));
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.start,
                spacing: 4,
                runSpacing: 8,
                children: lineWidgets,
              ),
            );
          }),
        ),
      );
    }

    if (q['type'] == 'SHORT_ANSWER') {
      final String prefix = q['shortAnswerPrefix'] ?? '';
      final String suffix = q['shortAnswerSuffix'] ?? '';
      final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];
      final String correctAnswer = correctAnswers.isNotEmpty
          ? correctAnswers[0].toString()
          : '';
      final bool isAnswerLatex = _isLatex(correctAnswer);
      final String currentValue = (selected.isNotEmpty) ? selected[0] : '';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showShortAnswerHint) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8, left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: context.isDark
                    ? const Color(0xFF1E1B4B)
                    : const Color(0xFFEEF2F6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(
                    0xFF6366F1,
                  ).withOpacity(context.isDark ? 0.5 : 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFF6366F1,
                    ).withOpacity(context.isDark ? 0.15 : 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lightbulb_rounded,
                    color: Colors.amber,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  LatexRichText(
                    text: q['shortAnswerHint'] ?? '',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 150.ms).scaleY(begin: 0.8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: context.isDark ? context.glassBg : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (prefix.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: LatexRichText(
                      text: prefix,
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                if (isAnswerLatex) ...[
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _hasSubmittedCurrentQuestion
                                ? null
                                : () => _showMathDialog(_currentQuestionIndex),
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: context.isDark
                                    ? context.glassBg
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _hasSubmittedCurrentQuestion
                                      ? (context.isDark
                                            ? context.glassBorder
                                            : const Color(0xFFE2E8F0))
                                      : (context.isDark
                                            ? const Color(
                                                0xFF6366F1,
                                              ).withOpacity(0.4)
                                            : const Color(0xFFCBD5E1)),
                                  width: 1.0,
                                ),
                              ),
                              alignment: Alignment.centerLeft,
                              child: currentValue.isEmpty
                                  ? Text(
                                      'Tap to write math formula...',
                                      style: TextStyle(
                                        color: context.textColor54.withOpacity(
                                          0.4,
                                        ),
                                        fontSize: 14,
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: LatexRichText(
                                        text: '\$$currentValue\$',
                                        style: TextStyle(
                                          color: context.textColor,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        if (!_hasSubmittedCurrentQuestion) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.calculate,
                              color: Color(0xFF6366F1),
                              size: 28,
                            ),
                            onPressed: () =>
                                _showMathDialog(_currentQuestionIndex),
                            tooltip: 'Open Math Keyboard',
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: TextField(
                      focusNode: _shortAnswerFocusNode,
                      style: TextStyle(color: context.textColor),
                      enabled: !_hasSubmittedCurrentQuestion,
                      decoration: InputDecoration(
                        hintText: 'Type your answer here...',
                        hintStyle: TextStyle(
                          color: context.textColor54.withOpacity(0.4),
                        ),
                        filled: true,
                        fillColor: context.isDark
                            ? context.glassBg
                            : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: context.isDark
                                ? context.glassBorder
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF6366F1),
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _selectedAnswers[_currentQuestionIndex] = [val];
                        });
                        _updateHintVisibility();
                        _saveProgress();
                      },
                    ),
                  ),
                ],
                if (suffix.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 12),
                    child: LatexRichText(
                      text: suffix,
                      style: TextStyle(
                        color: context.textColor70,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    if (q['type'] == 'GEOMETRIC') {
      final bool showResult = _hasSubmittedCurrentQuestion;
      final List<dynamic> nodes = q['geometryNodes'] ?? [];

      return LayoutBuilder(
        builder: (ctx, constraints) {
          final double width = constraints.maxWidth.clamp(0.0, 650.0);
          final double height = width * 0.75; // 4:3 Aspect Ratio
          return Center(
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.glassBorder),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. Background image
                  if (q['questionImage'] != null &&
                      q['questionImage'].toString().isNotEmpty)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: _renderImageOrSvg(
                          q['questionImage'],
                          isSvg: q['isSvg'] == true,
                        ),
                      ),
                    ),

                  // 2. Snapped lines (Custom Painter)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: GeometryPainter(_geometryLines, width, height),
                      ),
                    ),
                  ),

                  // 3. snapping target points (nodes)
                  if (q['hideGeometryNodes'] != true)
                    ...nodes.map((node) {
                      final double nx = (node['x'] as num).toDouble() / 100;
                      final double ny = (node['y'] as num).toDouble() / 100;
                      final bool isFixed = node['isFixed'] == true;

                      return Positioned(
                        left: nx * width - 12,
                        top: ny * height - 12,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFixed
                                ? (context.isDark
                                      ? Colors.blue.withOpacity(0.85)
                                      : const Color(0xFF3B82F6))
                                : (context.isDark
                                      ? Colors.black.withOpacity(0.85)
                                      : const Color(0xFF1E293B)),
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              node['label'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),

                  // 4. Draggable Handles for each movable line
                  ...List.generate(_geometryLines.length, (lineIdx) {
                    final line = _geometryLines[lineIdx];

                    // Translate fractional coords to screen coordinates
                    final double x1 = line.p1.dx * width;
                    final double y1 = line.p1.dy * height;
                    final double x2 = line.p2.dx * width;
                    final double y2 = line.p2.dy * height;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Endpoint 1 Handle
                        Positioned(
                          left: x1 - 20,
                          top: y1 - 20,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              if (showResult) return;
                              setState(() {
                                final double deltaX = details.delta.dx / width;
                                final double deltaY = details.delta.dy / height;
                                final double newX = (line.p1.dx + deltaX).clamp(
                                  0.0,
                                  1.0,
                                );
                                final double newY = (line.p1.dy + deltaY).clamp(
                                  0.0,
                                  1.0,
                                );
                                _geometryLines[lineIdx].p1 = Offset(newX, newY);
                                _geometryLines[lineIdx].node1Id =
                                    null; // clear snap
                              });
                            },
                            onPanEnd: (details) {
                              if (showResult) return;
                              _snapEndpoint(
                                lineIdx,
                                isEnd1: true,
                                width: width,
                                height: height,
                              );
                            },
                            child: _buildGeometryHandle(
                              isSnapped: line.node1Id != null,
                            ),
                          ),
                        ),

                        // Endpoint 2 Handle
                        Positioned(
                          left: x2 - 20,
                          top: y2 - 20,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              if (showResult) return;
                              setState(() {
                                final double deltaX = details.delta.dx / width;
                                final double deltaY = details.delta.dy / height;
                                final double newX = (line.p2.dx + deltaX).clamp(
                                  0.0,
                                  1.0,
                                );
                                final double newY = (line.p2.dy + deltaY).clamp(
                                  0.0,
                                  1.0,
                                );
                                _geometryLines[lineIdx].p2 = Offset(newX, newY);
                                _geometryLines[lineIdx].node2Id =
                                    null; // clear snap
                              });
                            },
                            onPanEnd: (details) {
                              if (showResult) return;
                              _snapEndpoint(
                                lineIdx,
                                isEnd1: false,
                                width: width,
                                height: height,
                              );
                            },
                            child: _buildGeometryHandle(
                              isSnapped: line.node2Id != null,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          );
        },
      );
    }

    if (q['type'] == 'MATRIX_INPUT') {
      final bool showResult = _hasSubmittedCurrentQuestion;
      final List<dynamic> rows = q['options'] ?? [];
      final List<dynamic> cols = q['rightOptions'] ?? [];
      final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];
      final List<dynamic> currentSelection =
          _selectedAnswers[_currentQuestionIndex] ?? [];

      final List<Map<String, int>> inputFieldCoords = [];
      for (int r = 0; r < rows.length; r++) {
        final String jsonStr = rows[r]['text'] ?? '[]';
        List<dynamic> cells = [];
        try {
          cells = json.decode(jsonStr);
        } catch (_) {}
        for (int c = 0; c < cells.length && c < cols.length; c++) {
          if (cells[c]['isInput'] == true) {
            inputFieldCoords.add({'r': r, 'c': c});
          }
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(150.0),
              border: TableBorder.all(color: context.glassBorder, width: 1),
              children: [
                // Header row
                TableRow(
                  decoration: BoxDecoration(
                    color: context.isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white.withOpacity(0.5),
                  ),
                  children: [
                    ...List.generate(cols.length, (colIdx) {
                      final colText = cols[colIdx]['text'] ?? '';
                      return TableCell(
                        verticalAlignment: TableCellVerticalAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Center(
                            child: LatexRichText(
                              text: colText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.textColor70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),

                // Data rows
                ...List.generate(rows.length, (rowIdx) {
                  final String jsonStr = rows[rowIdx]['text'] ?? '[]';
                  List<dynamic> cells = [];
                  try {
                    cells = json.decode(jsonStr);
                  } catch (_) {}
                  final bool isOdd = rowIdx % 2 != 0;

                  return TableRow(
                    decoration: BoxDecoration(
                      color: isOdd
                          ? (context.isDark
                                ? const Color(0xFF1E293B).withOpacity(0.15)
                                : Colors.black.withOpacity(0.02))
                          : Colors.transparent,
                    ),
                    children: [
                      ...List.generate(cols.length, (colIdx) {
                        final cell = (colIdx < cells.length)
                            ? cells[colIdx]
                            : {'value': '', 'isInput': false};
                        final bool isInput = cell['isInput'] == true;
                        final String cellValue = cell['value'] ?? '';

                        if (!isInput) {
                          return TableCell(
                            verticalAlignment:
                                TableCellVerticalAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              child: Center(
                                child: LatexRichText(
                                  text: cellValue,
                                  style: TextStyle(
                                    color: context.textColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        final int inputIdx = inputFieldCoords.indexWhere(
                          (coord) =>
                              coord['r'] == rowIdx && coord['c'] == colIdx,
                        );
                        final String currentValue =
                            (inputIdx >= 0 &&
                                inputIdx < currentSelection.length)
                            ? currentSelection[inputIdx]
                            : '';
                        final bool isCorrect =
                            (inputIdx >= 0 &&
                                inputIdx < correctAnswers.length) &&
                            (currentValue.trim().toLowerCase() ==
                                correctAnswers[inputIdx]
                                    .toString()
                                    .trim()
                                    .toLowerCase());

                        return TableCell(
                          verticalAlignment: TableCellVerticalAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: TextFormField(
                              initialValue: currentValue,
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 14,
                              ),
                              enabled: !showResult,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.all(10),
                                hintText: showResult ? '' : '?',
                                hintStyle: TextStyle(
                                  color: context.textColor54.withOpacity(0.4),
                                ),
                                filled: true,
                                fillColor: showResult
                                    ? (isCorrect
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1))
                                    : (context.isDark
                                          ? context.glassBg
                                          : const Color(0xFFF8FAFC)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: showResult
                                        ? (isCorrect
                                              ? Colors.green
                                              : Colors.redAccent)
                                        : context.glassBorder,
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: isCorrect
                                        ? Colors.green
                                        : Colors.redAccent,
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF6366F1),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  while (_selectedAnswers[_currentQuestionIndex]!
                                          .length <=
                                      inputIdx) {
                                    _selectedAnswers[_currentQuestionIndex]!
                                        .add("");
                                  }
                                  _selectedAnswers[_currentQuestionIndex]![inputIdx] =
                                      val;
                                });
                                _saveProgress();
                              },
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      );
    }

    if (q['type'] == 'MATRIX_MCQ') {
      final bool showResult = _hasSubmittedCurrentQuestion;
      final List<dynamic> rows = q['options'] ?? [];
      final List<dynamic> cols = q['rightOptions'] ?? [];
      final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];
      final List<dynamic> currentSelection =
          _selectedAnswers[_currentQuestionIndex] ?? [];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(130.0),
              border: TableBorder.all(color: context.glassBorder, width: 1),
              children: [
                // Header row
                TableRow(
                  decoration: BoxDecoration(
                    color: context.isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white.withOpacity(0.5),
                  ),
                  children: [
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text(
                          'Items',
                          style: TextStyle(
                            color: context.textColor70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    ...List.generate(cols.length, (colIdx) {
                      final colText = cols[colIdx]['text'] ?? '';
                      return TableCell(
                        verticalAlignment: TableCellVerticalAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Center(
                            child: LatexRichText(
                              text: colText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.textColor70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),

                // Data rows
                ...List.generate(rows.length, (rowIdx) {
                  final rowText = rows[rowIdx]['text'] ?? '';
                  final String selectedColStr =
                      (rowIdx < currentSelection.length)
                      ? currentSelection[rowIdx].toString()
                      : "";
                  final int selectedCol = int.tryParse(selectedColStr) ?? -1;
                  final bool isOdd = rowIdx % 2 != 0;

                  return TableRow(
                    decoration: BoxDecoration(
                      color: isOdd
                          ? (context.isDark
                                ? const Color(0xFF1E293B).withOpacity(0.15)
                                : Colors.black.withOpacity(0.02))
                          : Colors.transparent,
                    ),
                    children: [
                      // Row Label
                      TableCell(
                        verticalAlignment: TableCellVerticalAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: LatexRichText(
                            text: rowText,
                            style: TextStyle(
                              color: context.textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),

                      // Column options (Radio buttons)
                      ...List.generate(cols.length, (colIdx) {
                        final bool isSelected = selectedCol == colIdx;
                        final bool isCorrectChoice =
                            (rowIdx < correctAnswers.length) &&
                            (correctAnswers[rowIdx].toString() ==
                                colIdx.toString());

                        // Visual styling when answer is submitted
                        Color checkBorderColor = isSelected
                            ? const Color(0xFF6366F1)
                            : context.glassBorder;
                        Color? fillColor;

                        if (showResult) {
                          if (isSelected) {
                            if (isCorrectChoice) {
                              checkBorderColor = Colors.green;
                              fillColor = Colors.green;
                            } else {
                              checkBorderColor = Colors.redAccent;
                              fillColor = Colors.redAccent;
                            }
                          } else {
                            if (isCorrectChoice) {
                              checkBorderColor = Colors.green;
                              fillColor = Colors.green.withOpacity(0.2);
                            }
                          }
                        }

                        return TableCell(
                          verticalAlignment: TableCellVerticalAlignment.middle,
                          child: InkWell(
                            onTap: showResult
                                ? null
                                : () {
                                    setState(() {
                                      while (_selectedAnswers[_currentQuestionIndex]!
                                              .length <=
                                          rowIdx) {
                                        _selectedAnswers[_currentQuestionIndex]!
                                            .add("");
                                      }
                                      _selectedAnswers[_currentQuestionIndex]![rowIdx] =
                                          colIdx.toString();
                                    });
                                    _saveProgress();
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: Center(
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: checkBorderColor,
                                      width: isSelected ? 6.5 : 2,
                                    ),
                                    color: fillColor ?? Colors.transparent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      );
    }

    if (q['type'] == 'MATCHING') {
      final bool showResult = _hasSubmittedCurrentQuestion;
      final List<dynamic> leftOptions = q['options'] ?? [];
      final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column (Fixed)
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leftOptions.length,
              itemBuilder: (ctx, idx) {
                final opt = leftOptions[idx];
                return Container(
                  height: 90,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: context.isDark ? context.glassBg : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: context.isDark
                          ? context.glassBorder
                          : const Color(0xFF8B5CF6).withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF6366F1),
                        ),
                        child: Text(
                          '${idx + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (opt['text'] != null &&
                                opt['text'].toString().isNotEmpty)
                              LatexRichText(
                                text: opt['text'],
                                style: GoogleFonts.outfit(
                                  color: context.textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (opt['imageUrl'] != null &&
                                opt['imageUrl'].toString().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              _renderImageOrSvg(
                                opt['imageUrl'],
                                isSvg: opt['isSvg'] == true,
                                height: 40,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: 12),

          // Right Column (Reorderable)
          Expanded(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _matchingRightOptions.length,
              itemBuilder: (ctx, idx) {
                final opt = _matchingRightOptions[idx];
                final String originalIdxStr = (q['rightOptions'] ?? [])
                    .indexOf(opt)
                    .toString();

                // Connection is correct if Right Option index matches Left Option index
                bool isPlacedCorrectly = false;
                if (idx < correctAnswers.length) {
                  isPlacedCorrectly =
                      correctAnswers[idx].toString() == originalIdxStr;
                }

                Color cardColor = context.isDark
                    ? context.glassBg
                    : Colors.white;
                Color borderClr = context.isDark
                    ? context.glassBorder
                    : const Color(0xFF8B5CF6).withOpacity(0.15);

                if (showResult) {
                  cardColor = isPlacedCorrectly
                      ? Colors.green.withOpacity(0.12)
                      : Colors.red.withOpacity(0.12);
                  borderClr = isPlacedCorrectly
                      ? Colors.green.withOpacity(0.4)
                      : Colors.red.withOpacity(0.4);
                }

                return Container(
                  key: ValueKey(opt),
                  height: 90,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderClr, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (opt['text'] != null &&
                                opt['text'].toString().isNotEmpty)
                              LatexRichText(
                                text: opt['text'],
                                style: GoogleFonts.outfit(
                                  color: context.textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (opt['imageUrl'] != null &&
                                opt['imageUrl'].toString().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              _renderImageOrSvg(
                                opt['imageUrl'],
                                isSvg: opt['isSvg'] == true,
                                height: 40,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      showResult
                          ? (isPlacedCorrectly
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.green,
                                    size: 20,
                                  )
                                : const Icon(
                                    Icons.cancel_rounded,
                                    color: Colors.red,
                                    size: 20,
                                  ))
                          : Icon(
                              Icons.drag_handle_rounded,
                              color: context.textColor54.withOpacity(0.5),
                              size: 20,
                            ),
                    ],
                  ),
                );
              },
              onReorder: (oldIndex, newIndex) {
                if (showResult) return;
                setState(() {
                  if (newIndex > oldIndex) {
                    newIndex -= 1;
                  }
                  final item = _matchingRightOptions.removeAt(oldIndex);
                  _matchingRightOptions.insert(newIndex, item);

                  final List<dynamic> dbRight = q['rightOptions'] ?? [];
                  final List<String> currentOrder = _matchingRightOptions.map((
                    opt,
                  ) {
                    return dbRight.indexOf(opt).toString();
                  }).toList();
                  _selectedAnswers[_currentQuestionIndex] = currentOrder;
                });
                _saveProgress();
              },
            ),
          ),
        ],
      );
    }

    if (q['type'] == 'ORDERING') {
      final bool showResult = _hasSubmittedCurrentQuestion;
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _orderingOptions.length,
        itemBuilder: (ctx, idx) {
          final opt = _orderingOptions[idx];
          final String originalIdxStr = q['options'].indexOf(opt).toString();

          final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];
          bool isPlacedCorrectly = false;
          if (idx < correctAnswers.length) {
            isPlacedCorrectly =
                correctAnswers[idx].toString() == originalIdxStr;
          }

          Color cardColor = context.isDark ? context.glassBg : Colors.white;
          Color borderClr = context.isDark
              ? context.glassBorder
              : const Color(0xFF8B5CF6).withOpacity(0.15);

          if (showResult) {
            if (isPlacedCorrectly) {
              cardColor = Colors.green.withOpacity(0.12);
              borderClr = Colors.green.withOpacity(0.4);
            } else {
              cardColor = Colors.red.withOpacity(0.12);
              borderClr = Colors.red.withOpacity(0.4);
            }
          }

          return Container(
            key: ValueKey(opt),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderClr, width: 1.5),
            ),
            child: ListTile(
              enabled: !showResult,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.isDark
                      ? context.glassBg
                      : const Color(0xFFF1F5F9),
                ),
                child: Text(
                  '${idx + 1}',
                  style: TextStyle(
                    color: context.textColor70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Row(
                children: [
                  if (opt['text'] != null && opt['text'].toString().isNotEmpty)
                    Expanded(
                      child: LatexRichText(
                        text: opt['text'],
                        style: GoogleFonts.outfit(
                          color: context.textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (opt['imageUrl'] != null &&
                      opt['imageUrl'].toString().isNotEmpty) ...[
                    const SizedBox(width: 12),
                    _renderImageOrSvg(
                      opt['imageUrl'],
                      isSvg: opt['isSvg'] == true,
                      height: 50,
                      width: 80,
                    ),
                  ],
                ],
              ),
              trailing: showResult
                  ? (isPlacedCorrectly
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.green,
                          )
                        : const Icon(Icons.cancel_rounded, color: Colors.red))
                  : Icon(
                      Icons.drag_handle_rounded,
                      color: context.textColor54.withOpacity(0.5),
                    ),
            ),
          );
        },
        onReorder: (oldIndex, newIndex) {
          if (showResult) return;
          setState(() {
            if (newIndex > oldIndex) {
              newIndex -= 1;
            }
            final item = _orderingOptions.removeAt(oldIndex);
            _orderingOptions.insert(newIndex, item);

            final List<dynamic> dbOptions = q['options'];
            final List<String> currentOrder = _orderingOptions.map((opt) {
              return dbOptions.indexOf(opt).toString();
            }).toList();
            _selectedAnswers[_currentQuestionIndex] = currentOrder;
          });
          _saveProgress();
        },
      );
    }

    final List<dynamic> options = q['options'] ?? [];

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: options.length,
      itemBuilder: (ctx, idx) {
        final opt = options[idx];
        final String indexStr = idx.toString();
        final bool isSelected = selected.contains(indexStr);
        final bool showResult = _hasSubmittedCurrentQuestion;

        final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];
        final bool isCorrectOpt = correctAnswers
            .map((e) => e.toString())
            .contains(indexStr);

        Color cardColor = context.isDark
            ? context.glassBg
            : Colors.white.withOpacity(0.95);
        Color borderClr = context.isDark
            ? context.glassBorder
            : const Color(0xFF8B5CF6).withOpacity(0.15);

        if (showResult) {
          if (isCorrectOpt) {
            cardColor = Colors.green.withOpacity(0.12);
            borderClr = Colors.green.withOpacity(0.4);
          } else if (isSelected) {
            cardColor = Colors.red.withOpacity(0.12);
            borderClr = Colors.red.withOpacity(0.4);
          }
        } else if (isSelected) {
          cardColor = const Color(0xFF6366F1).withOpacity(0.12);
          borderClr = const Color(0xFF6366F1);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderClr, width: 1.5),
          ),
          child: ListTile(
            enabled: !_hasSubmittedCurrentQuestion,
            onTap: () {
              setState(() {
                if (q['type'] == 'MCQ_SINGLE') {
                  _selectedAnswers[_currentQuestionIndex] = [indexStr];
                } else {
                  // MCQ_MULTI toggle
                  final List<String> current = List.from(selected);
                  if (current.contains(indexStr)) {
                    current.remove(indexStr);
                  } else {
                    current.add(indexStr);
                  }
                  _selectedAnswers[_currentQuestionIndex] = current;
                }
              });
              _saveProgress();
            },
            leading: _buildOptionSelectionIndicator(
              q['type'],
              isSelected,
              showResult,
              isCorrectOpt,
            ),
            title: Row(
              children: [
                if (opt['text'] != null && opt['text'].toString().isNotEmpty)
                  Expanded(
                    child: LatexRichText(
                      text: opt['text'],
                      style: GoogleFonts.outfit(
                        color: context.textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (opt['imageUrl'] != null &&
                    opt['imageUrl'].toString().isNotEmpty) ...[
                  const SizedBox(width: 12),
                  _renderImageOrSvg(
                    opt['imageUrl'],
                    isSvg: opt['isSvg'] == true,
                    height: 50,
                    width: 80,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // MCQ radio/checkbox visual indicator
  Widget _buildOptionSelectionIndicator(
    String type,
    bool isSelected,
    bool showResult,
    bool isCorrect,
  ) {
    if (showResult) {
      if (isCorrect) {
        return const Icon(Icons.check_circle_rounded, color: Colors.green);
      }
      if (isSelected) {
        return const Icon(Icons.cancel_rounded, color: Colors.red);
      }
    }

    if (type == 'MCQ_SINGLE') {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1)
                : (context.isDark ? Colors.white30 : Colors.black26),
            width: 2,
          ),
        ),
        child: isSelected
            ? Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF6366F1),
                  ),
                ),
              )
            : null,
      );
    } else {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1)
                : (context.isDark ? Colors.white30 : Colors.black26),
            width: 2,
          ),
        ),
        child: isSelected
            ? const Center(
                child: Icon(Icons.check, size: 14, color: Color(0xFF6366F1)),
              )
            : null,
      );
    }
  }

  // Correction feedback details banner
  Widget _buildFeedbackBanner(dynamic q) {
    final bool correct = _questionFeedback[_currentQuestionIndex] ?? false;
    final List<dynamic> correctAnswers = q['correctAnswers'] ?? [];

    String correctMsg = '';
    if (q['type'] == 'SHORT_ANSWER') {
      correctMsg = correctAnswers.first.toString();
    } else if (q['type'] == 'MATCHING') {
      final List<dynamic> left = q['options'] ?? [];
      final List<dynamic> right = q['rightOptions'] ?? [];
      final List<String> pairs = [];
      for (int i = 0; i < left.length && i < right.length; i++) {
        final lText = left[i]['text'] ?? '';
        final rText = right[i]['text'] ?? '';
        pairs.add(
          '${lText.isNotEmpty ? lText : "Item ${i + 1}"} ➔ ${rText.isNotEmpty ? rText : "Match ${i + 1}"}',
        );
      }
      correctMsg = pairs.join(', ');
    } else if (q['type'] == 'MATRIX_MCQ') {
      final List<dynamic> rows = q['options'] ?? [];
      final List<dynamic> cols = q['rightOptions'] ?? [];
      final List<String> feedbackLines = [];
      for (int i = 0; i < rows.length && i < correctAnswers.length; i++) {
        final rowText = rows[i]['text'] ?? 'Row ${i + 1}';
        final colIdx = int.tryParse(correctAnswers[i].toString()) ?? -1;
        final colText = (colIdx >= 0 && colIdx < cols.length)
            ? cols[colIdx]['text']
            : '';
        feedbackLines.add('$rowText ➔ $colText');
      }
      correctMsg = feedbackLines.join(', ');
    } else if (q['type'] == 'MATRIX_INPUT' ||
        q['type'] == 'EQUATION' ||
        q['type'] == 'STATEMENT_DROPDOWN' ||
        q['type'] == 'INLINE_SELECT') {
      final List<dynamic> correct = q['correctAnswers'] ?? [];
      correctMsg = 'Values: ' + correct.map((e) => e.toString()).join(', ');
    } else if (q['type'] == 'GEOMETRIC') {
      final List<dynamic> nodes = q['geometryNodes'] ?? [];
      final List<String> conns = [];
      for (var c in correctAnswers) {
        final parts = c.toString().split('-');
        if (parts.length == 2) {
          final n1 = nodes.firstWhere(
            (n) => n['id'] == parts[0],
            orElse: () => null,
          );
          final n2 = nodes.firstWhere(
            (n) => n['id'] == parts[1],
            orElse: () => null,
          );
          final label1 = n1 != null && n1['label'].toString().isNotEmpty
              ? n1['label']
              : 'Point';
          final label2 = n2 != null && n2['label'].toString().isNotEmpty
              ? n2['label']
              : 'Point';
          conns.add('$label1 ➔ $label2');
        }
      }
      correctMsg = 'Connect: ' + conns.join(', ');
    } else {
      // Find options index text
      final List<dynamic> options = q['options'] ?? [];
      final List<String> texts = [];
      for (var c in correctAnswers) {
        final idx = int.tryParse(c.toString());
        if (idx != null && idx < options.length) {
          final oText = options[idx]['text'] ?? '';
          texts.add(oText.isNotEmpty ? oText : 'Item ${idx + 1}');
        }
      }
      correctMsg = q['type'] == 'ORDERING'
          ? texts.join(' ➔ ')
          : texts.join(', ');
    }

    final feedbackWidget = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: correct
            ? Colors.green.withOpacity(0.08)
            : Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: correct
              ? Colors.green.withOpacity(0.2)
              : Colors.red.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                correct ? Icons.check_circle : Icons.error_rounded,
                color: correct ? Colors.green : Colors.redAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                correct ? 'Well Done!' : 'Incorrect Answer',
                style: TextStyle(
                  color: correct ? Colors.green : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (!correct) ...[
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Correct Answer: ',
                  style: TextStyle(color: context.textColor70, fontSize: 13),
                ),
                LatexRichText(
                  text: _isLatex(correctMsg) && !correctMsg.contains('\$')
                      ? '\$$correctMsg\$'
                      : correctMsg,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
          _buildStepByStepExplanation(q),
        ],
      ),
    ).animate().slideY(begin: 0.1, end: 0, curve: Curves.easeOut);

    return feedbackWidget;
  }

  Widget _buildStepByStepExplanation(dynamic q) {
    final String explanationText = q['explanation'] ?? '';
    final List<dynamic> steps = q['explanationSteps'] ?? [];

    if (explanationText.isEmpty && steps.isEmpty) return const SizedBox();

    final isDark = context.isDark;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF3B82F6).withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lightbulb_rounded,
                  color: Color(0xFF3B82F6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Step-by-Step Solution Explanation',
                style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (explanationText.isNotEmpty) ...[
            const SizedBox(height: 10),
            LatexRichText(
              text: explanationText,
              style: TextStyle(
                color: context.textColor,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...List.generate(steps.length, (idx) {
              final step = steps[idx];
              final int stepNum = step['stepNumber'] ?? (idx + 1);
              final List<dynamic> blocks = step['blocks'] ?? [];

              final List<Widget> blockWidgets = [];
              if (blocks.isNotEmpty) {
                for (var b in blocks) {
                  final String bType = b['type'] ?? 'TEXT';
                  final String content = b['content'] ?? '';
                  final bool isSvg = b['isSvg'] == true;

                  if (content.isEmpty) continue;

                  if (bType == 'IMAGE') {
                    blockWidgets.add(
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _renderImageOrSvg(
                            content,
                            isSvg: isSvg,
                            height: 150,
                          ),
                        ),
                      ),
                    );
                  } else {
                    blockWidgets.add(
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: LatexRichText(
                          text: content,
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 14,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }
                }
              } else {
                final String stepText = step['text'] ?? '';
                final String stepImg = step['imageUrl'] ?? '';
                final bool isSvg = step['isSvg'] == true;

                if (stepText.isNotEmpty) {
                  blockWidgets.add(
                    LatexRichText(
                      text: stepText,
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }
                if (stepImg.isNotEmpty) {
                  blockWidgets.add(
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _renderImageOrSvg(
                          stepImg,
                          isSvg: isSvg,
                          height: 140,
                        ),
                      ),
                    ),
                  );
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 14.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step Badge: e.g., "1 / 3"
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$stepNum / ${steps.length}',
                        style: const TextStyle(
                          color: Color(0xFF3B82F6),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Step Content Box with left accent line
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.only(left: 12),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Color(0xFF3B82F6),
                              width: 2.5,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: blockWidgets,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // Handle rendering SVG code, SVG url or regular image
  Widget _renderImageOrSvg(
    String path, {
    required bool isSvg,
    double? height,
    double? width,
  }) {
    final fullUrl = _getImageUrl(path);

    if (isSvg) {
      // Check if it's a relative/absolute url or inline XML
      if (path.contains('<svg') || path.contains('<path')) {
        return SvgPicture.string(
          path,
          height: height,
          width: width,
          fit: BoxFit.contain,
        );
      }
      return SvgPicture.network(
        fullUrl,
        height: height,
        width: width,
        fit: BoxFit.contain,
        placeholderBuilder: (context) => const SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: JyamitiLoader(
              strokeWidth: 1.5,
              color: Color(0xFF6366F1),
            ),
          ),
        ),
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.broken_image,
          color: context.textColor54.withOpacity(0.4),
          size: 24,
        ),
      );
    } else {
      return Image.network(
        fullUrl,
        height: height,
        width: width,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: JyamitiLoader(
                strokeWidth: 1.5,
                color: Color(0xFF6366F1),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.broken_image,
          color: context.textColor54.withOpacity(0.4),
          size: 24,
        ),
      );
    }
  }

  Widget _buildGeometryHandle({required bool isSnapped}) {
    return Container(
      width: 40,
      height: 40,
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.textColor,
            border: Border.all(
              color: isSnapped
                  ? const Color(0xFF10B981)
                  : const Color(0xFF3B82F6),
              width: 3,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSnapped
                    ? const Color(0xFF10B981)
                    : const Color(0xFF3B82F6),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _snapEndpoint(
    int lineIdx, {
    required bool isEnd1,
    required double width,
    required double height,
  }) {
    final line = _geometryLines[lineIdx];
    final currentPos = isEnd1 ? line.p1 : line.p2;

    final q = _questions[_currentQuestionIndex];
    final List<dynamic> nodes = q['geometryNodes'] ?? [];

    String? closestNodeId;
    Offset? closestNodeFractional;
    double minDistance = double.maxFinite;

    for (var n in nodes) {
      final double nx = (n['x'] as num).toDouble() / 100;
      final double ny = (n['y'] as num).toDouble() / 100;

      final double dx = (nx - currentPos.dx) * width;
      final double dy = (ny - currentPos.dy) * height;
      final double distance = sqrt(dx * dx + dy * dy);

      if (distance < minDistance) {
        minDistance = distance;
        closestNodeId = n['id'];
        closestNodeFractional = Offset(nx, ny);
      }
    }

    if (minDistance < 30.0 &&
        closestNodeId != null &&
        closestNodeFractional != null) {
      setState(() {
        if (isEnd1) {
          line.p1 = closestNodeFractional!;
          line.node1Id = closestNodeId;
        } else {
          line.p2 = closestNodeFractional!;
          line.node2Id = closestNodeId;
        }
        _updateSelectedConnections();
      });
    }
  }

  void _updateSelectedConnections() {
    final List<String> currentConns = [];
    for (var line in _geometryLines) {
      if (line.node1Id != null && line.node2Id != null) {
        final sorted = [line.node1Id!, line.node2Id!]..sort();
        currentConns.add('${sorted[0]}-${sorted[1]}');
      }
    }
    _selectedAnswers[_currentQuestionIndex] = currentConns;
    _saveProgress();
  }
}

class LineState {
  Offset p1; // fractional coordinate
  String? node1Id;
  Offset p2; // fractional coordinate
  String? node2Id;

  LineState({required this.p1, required this.p2, this.node1Id, this.node2Id});
}

class GeometryPainter extends CustomPainter {
  final List<LineState> lines;
  final double width;
  final double height;

  GeometryPainter(this.lines, this.width, this.height);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6366F1)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    for (var line in lines) {
      final p1Pixel = Offset(line.p1.dx * width, line.p1.dy * height);
      final p2Pixel = Offset(line.p2.dx * width, line.p2.dy * height);
      canvas.drawLine(p1Pixel, p2Pixel, paint);
    }
  }

  @override
  bool shouldRepaint(covariant GeometryPainter oldDelegate) => true;
}
