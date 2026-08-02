import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../providers/theme_provider.dart';
import 'package:math_keyboard/math_keyboard.dart';
import '../../../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────
//  MAIN SCREEN (load exam, then show ExamForm)
// ─────────────────────────────────────────────────────────────
class ExamTakingScreen extends StatefulWidget {
  final String examId;
  const ExamTakingScreen({super.key, required this.examId});

  @override
  State<ExamTakingScreen> createState() => _ExamTakingScreenState();
}

class _ExamTakingScreenState extends State<ExamTakingScreen> {
  Map<String, dynamic>? _exam;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchExam();
  }

  Future<void> _fetchExam() async {
    try {
      final res = await ApiService.get('/exams/${widget.examId}');
      if (res.statusCode == 200) {
        setState(() { _exam = jsonDecode(res.body); _isLoading = false; });
      } else if (res.statusCode == 403) {
        setState(() { _error = 'You have already submitted this exam.'; _isLoading = false; });
      } else {
        setState(() { _error = 'Failed to load exam.'; _isLoading = false; });
      }
    } catch (_) {
      setState(() { _error = 'Error loading exam.'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        body: const Center(child: JyamitiLoader(color: Color(0xFF6366F1))),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: Text('Exam', style: TextStyle(color: context.textColor)),
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          iconTheme: IconThemeData(color: context.textColor),
        ),
        body: Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 16))),
      );
    }

    // Calculate end time from exam duration (in minutes)
    final durationMin = (_exam!['duration'] ?? 60) as int;
    final endTime = DateTime.now().add(Duration(minutes: durationMin));

    return Scaffold(
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(_exam!['title'] ?? 'Exam', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        iconTheme: IconThemeData(color: context.textColor),
        elevation: 0,
      ),
      body: MathKeyboardViewInsets(
        child: ExamForm(
          examId: widget.examId,
          questions: List<Map<String, dynamic>>.from(_exam!['questions'] ?? []),
          endTime: endTime,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  EXAM FORM (timer + navigator + page view + footer)
// ─────────────────────────────────────────────────────────────
class ExamForm extends StatefulWidget {
  final String examId;
  final List<Map<String, dynamic>> questions;
  final DateTime endTime;

  const ExamForm({super.key, required this.examId, required this.questions, required this.endTime});

  @override
  State<ExamForm> createState() => _ExamFormState();
}

class _ExamFormState extends State<ExamForm> {
  final Map<String, dynamic> _answers = {};
  final Map<String, TextEditingController> _textControllers = {};

  late Duration _remainingTime;
  late Duration _totalExamDuration;
  Timer? _timer;
  bool _isSubmitting = false;
  int _currentPageIndex = 0;
  late final PageController _pageController;
  late final ScrollController _navigatorScrollController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _navigatorScrollController = ScrollController();
    _totalExamDuration = widget.endTime.difference(DateTime.now());
    _remainingTime = widget.endTime.difference(DateTime.now());

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCenter(_currentPageIndex));

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final time = widget.endTime.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _remainingTime = time.isNegative ? Duration.zero : time);
      if (time.isNegative) {
        _timer?.cancel();
        _autoSubmitExam();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    _navigatorScrollController.dispose();
    for (final c in _textControllers.values) { c.dispose(); }
    super.dispose();
  }

  bool _canSubmitManually() {
    final elapsed = _totalExamDuration - _remainingTime;
    if (_totalExamDuration.inSeconds == 0) return true;
    final elapsedPercent = elapsed.inSeconds / _totalExamDuration.inSeconds;
    return elapsedPercent >= 0.30;
  }

  double _calculateCompletion() {
    if (widget.questions.isEmpty) return 0;
    final answered = _answers.keys.where((k) {
      final a = _answers[k];
      return a != null && (a is int || (a is String && a.isNotEmpty) || (a is List && a.isNotEmpty));
    }).length;
    return answered / widget.questions.length;
  }

  void _scrollToCenter(int index) {
    if (!_navigatorScrollController.hasClients) return;
    const itemWidth = 44.0; // 36 width + 2 x 4px horizontal margin
    final screenWidth = MediaQuery.of(context).size.width;
    final offset = (index * itemWidth) - (screenWidth / 2 - itemWidth / 2);
    final maxScroll = _navigatorScrollController.position.maxScrollExtent;
    final clampedOffset = offset.clamp(0.0, maxScroll);

    _navigatorScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // Auto-submit (no confirmation dialog when time runs out)
  Future<void> _autoSubmitExam() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    await _doSubmit();
  }

  // Manual submit — shows confirmation with 3-second OK delay
  void _submitExam() {
    if (_isSubmitting) return;
    bool okEnabled = false;
    Timer? enableOkTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          enableOkTimer ??= Timer(const Duration(seconds: 3), () {
            if (mounted) setSheet(() => okEnabled = true);
          });

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AlertDialog(
              backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: context.glassBorder)),
              title:  Text('Confirm Submission', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Text('Are you sure you want to submit the exam?', style: TextStyle(color: context.textColor70)),
                  const SizedBox(height: 16),
                  // Answered count summary
                  _buildSubmitSummary(),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () { enableOkTimer?.cancel(); Navigator.of(dialogContext).pop(); },
                  child: Text('Cancel', style: TextStyle(color: context.textColor60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: okEnabled ? const Color(0xFF6366F1) : Colors.grey.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: okEnabled
                      ? () {
                          Navigator.of(dialogContext).pop();
                          setState(() => _isSubmitting = true);
                          _doSubmit();
                        }
                      : null,
                  child: Text(okEnabled ? 'Submit' : 'Wait...', style: TextStyle(color: context.textColor)),
                ),
              ],
            ),
          );
        });
      },
    ).then((_) => enableOkTimer?.cancel());
  }

  Widget _buildSubmitSummary() {
    final total = widget.questions.length;
    final answered = _answers.keys.where((k) {
      final a = _answers[k];
      return a != null && (a is int || (a is String && a.isNotEmpty) || (a is List && a.isNotEmpty));
    }).length;
    final unanswered = total - answered;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.glassBg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _summaryItem('$answered', 'Answered', const Color(0xFF10B981)),
          _summaryItem('$unanswered', 'Skipped', Colors.orange),
          _summaryItem('$total', 'Total', const Color(0xFF6366F1)),
        ],
      ),
    );
  }

  Widget _summaryItem(String val, String label, Color color) {
    return Column(
      children: [
        Text(val, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: context.textColor54, fontSize: 12)),
      ],
    );
  }

  Future<void> _showMathDialog(String qId) async {
    String currentMath = '';
    final mathController = MathFieldEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        title:  Text('Insert Math Equation', style: TextStyle(color: context.textColor)),
        content: Container(
          width: double.maxFinite,
          color: context.isDark ? const Color(0xFF0F172A) : Colors.white,
          child: MathField(
            controller: mathController,
            variables: const ['x', 'y', 'z'],
            keyboardType: MathKeyboardType.expression,
            decoration: InputDecoration(
              hintText: 'Use math keyboard...',
              hintStyle: TextStyle(color: context.textColor54.withOpacity(0.5)),
              border: OutlineInputBorder(),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () {
              Navigator.pop(ctx, currentMath);
            },
            child: Text('Insert', style: TextStyle(color: context.textColor)),
          ),
        ],
      ),
    );

    mathController.dispose();

    if (result != null && result.isNotEmpty) {
      final ctrl = _textControllers[qId];
      if (ctrl != null) {
        final text = ctrl.text;
        final selection = ctrl.selection;
        final insertion = ' \\( $result \\) ';
        if (selection.isValid && selection.start >= 0) {
          final newText = text.replaceRange(selection.start, selection.end, insertion);
          ctrl.text = newText;
          ctrl.selection = TextSelection.collapsed(offset: selection.start + insertion.length);
        } else {
          ctrl.text = text + insertion;
          ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
        }
        setState(() => _answers[qId] = ctrl.text);
      }
    }
  }

  Future<void> _doSubmit() async {
    final List<Map<String, dynamic>> submitAnswers = [];
    for (final q in widget.questions) {
      final qId = q['_id'] as String;
      final type = q['type'] as String;
      final ans = _answers[qId];
      if (type == 'SHORT_ANSWER') {
        submitAnswers.add({'questionId': qId, 'textAnswer': ans ?? ''});
      } else {
        submitAnswers.add({'questionId': qId, 'selectedOptions': ans != null ? (ans is List ? ans : [ans]) : []});
      }
    }

    try {
      final res = await ApiService.post('/exams/${widget.examId}/submit', {'answers': submitAnswers});
      if (!mounted) return;
      if (res.statusCode == 201) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Submitted!', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
            content: Text('Your exam has been submitted successfully.', style: TextStyle(color: context.textColor70)),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                onPressed: () { Navigator.of(context)..pop()..pop(); },
                child: Text('OK', style: TextStyle(color: context.textColor)),
              ),
            ],
          ),
        );
      } else {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to submit exam.'), backgroundColor: Colors.redAccent));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error submitting exam.'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── 1. Timer + Progress Bar ──────────────────────────
        _ExamTimerBar(totalDuration: _totalExamDuration, remaining: _remainingTime, completion: _calculateCompletion()),

        // ── 2. Question Navigator ────────────────────────────
        _QuestionNavigator(
          questions: widget.questions,
          answers: _answers,
          currentIndex: _currentPageIndex,
          scrollController: _navigatorScrollController,
          onTap: (i) {
            _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
            _scrollToCenter(i);
          },
        ),

        // ── 3. Question Page View ────────────────────────────
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.questions.length,
            onPageChanged: (i) {
              setState(() => _currentPageIndex = i);
              _scrollToCenter(i);
            },
            itemBuilder: (ctx, i) => Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                child: _QuestionCard(
                  question: widget.questions[i],
                  index: i,
                  isSubmitting: _isSubmitting,
                  answers: _answers,
                  textControllers: _textControllers,
                  onAnswerChanged: (id, val) => setState(() => _answers[id] = val),
                  onInsertMath: (id) => _showMathDialog(id),
                ),
              ),
            ),
          ),
        ),

        // ── 4. Footer ────────────────────────────────────────
        _ExamFooter(
          currentIndex: _currentPageIndex,
          total: widget.questions.length,
          isSubmitting: _isSubmitting,
          canSubmit: _canSubmitManually(),
          onPrev: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
          onNext: () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
          onSubmit: _submitExam,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  WIDGET 1: Timer + Dual Progress Bar
// ─────────────────────────────────────────────────────────────
class _ExamTimerBar extends StatelessWidget {
  final Duration totalDuration;
  final Duration remaining;
  final double completion;

  const _ExamTimerBar({required this.totalDuration, required this.remaining, required this.completion});

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Color _timerColor() {
    if (totalDuration.inSeconds == 0) return const Color(0xFF10B981);
    final pct = remaining.inSeconds / totalDuration.inSeconds;
    if (pct > 0.5) return const Color(0xFF10B981);
    if (pct > 0.2) return const Color(0xFFF59E0B);
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final timePct = totalDuration.inSeconds == 0 ? 0.0 : (remaining.inSeconds / totalDuration.inSeconds).clamp(0.0, 1.0);
    final timerColor = _timerColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Timer
              Row(
                children: [
                  Icon(Icons.timer_rounded, color: timerColor, size: 18),
                  const SizedBox(width: 6),
                  Text(_format(remaining), style: TextStyle(color: timerColor, fontSize: 16, fontWeight: FontWeight.bold, fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
              // Completion %
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Text('${(completion * 100).toInt()}% done', style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Dual stacked progress bar
          Stack(
            children: [
              // Background
              Container(height: 6, decoration: BoxDecoration(color: context.glassBorder, borderRadius: BorderRadius.circular(3))),
              // Time elapsed
              FractionallySizedBox(
                widthFactor: timePct,
                child: Container(height: 6, decoration: BoxDecoration(
                  color: timerColor.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(3),
                )),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              Container(height: 4, decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), borderRadius: BorderRadius.circular(2))),
              FractionallySizedBox(
                widthFactor: completion.clamp(0.0, 1.0),
                child: Container(height: 4, decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(2),
                )),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Time', style: TextStyle(color: Colors.white38, fontSize: 10)),
              Text('Answered', style: TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  WIDGET 2: Horizontal Question Navigator
// ─────────────────────────────────────────────────────────────
//  WIDGET 2: Horizontal Question Navigator
// ─────────────────────────────────────────────────────────────
class _QuestionNavigator extends StatelessWidget {
  final List<Map<String, dynamic>> questions;
  final Map<String, dynamic> answers;
  final int currentIndex;
  final ScrollController scrollController;
  final void Function(int) onTap;

  const _QuestionNavigator({required this.questions, required this.answers, required this.currentIndex, required this.scrollController, required this.onTap});

  bool _isAnswered(Map<String, dynamic> q) {
    final a = answers[q['_id']];
    if (a == null) return false;
    if (a is String) return a.isNotEmpty;
    if (a is List) return a.isNotEmpty;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final answeredCount = questions.where(_isAnswered).length;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          top: BorderSide(color: context.glassBorder),
          bottom: BorderSide(color: context.glassBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: label + answered count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Questions',
                style: TextStyle(color: context.textColor70, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                ),
                child: Text(
                  '$answeredCount / ${questions.length} answered',
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Scrollable circular question buttons
          SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(questions.length, (i) {
                final isCurrent = i == currentIndex;
                final isAnswered = _isAnswered(questions[i]);

                // Colors matching reference: green fill if answered, transparent with border if current, grey if neither
                Color bgColor;
                Color borderColor;
                Color textColor;

                if (isAnswered) {
                  bgColor = const Color(0xFF10B981);
                  borderColor = const Color(0xFF10B981);
                  textColor = Colors.white;
                } else if (isCurrent) {
                  bgColor = Colors.transparent;
                  borderColor = const Color(0xFF6366F1);
                  textColor = const Color(0xFF6366F1);
                } else {
                  bgColor = Colors.white.withOpacity(0.07);
                  borderColor = Colors.white.withOpacity(0.2);
                  textColor = Colors.white54;
                }

                return GestureDetector(
                  onTap: () => onTap(i),
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: bgColor,
                      border: Border.all(
                        color: borderColor,
                        width: isCurrent ? 2.5 : 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  WIDGET 3: Question Card
// ─────────────────────────────────────────────────────────────
class _QuestionCard extends StatelessWidget {
  final Map<String, dynamic> question;
  final int index;
  final bool isSubmitting;
  final Map<String, dynamic> answers;
  final Map<String, TextEditingController> textControllers;
  final void Function(String id, dynamic val) onAnswerChanged;
  final void Function(String id) onInsertMath;

  const _QuestionCard({
    required this.question, required this.index, required this.isSubmitting,
    required this.answers, required this.textControllers,
    required this.onAnswerChanged, required this.onInsertMath,
  });

  @override
  Widget build(BuildContext context) {
    final q = question;
    final type = q['type'] as String;
    final qId = q['_id'] as String;

    if (type == 'SHORT_ANSWER' && !textControllers.containsKey(qId)) {
      textControllers[qId] = TextEditingController(text: answers[qId] ?? '');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.glassBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.25)),
              boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.05), blurRadius: 12)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text('${index + 1}', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 14))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(q['text'] ?? '', style: TextStyle(color: context.textColor, fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _buildChip(_typeLabel(type), const Color(0xFF818CF8)),
                            const SizedBox(width: 8),
                            _buildChip('${q['marks']} marks', const Color(0xFFF59E0B)),
                          ],
                        ),
                      ],
                    )),
                    if (type == 'SHORT_ANSWER')
                      GestureDetector(
                        onTap: () => onInsertMath(qId),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                          child: const Row(
                            children: [
                              Icon(Icons.calculate_outlined, color: Color(0xFF6366F1), size: 16),
                              SizedBox(width: 4),
                              Text('Insert Math', style: TextStyle(color: Color(0xFF6366F1), fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Answer area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.glassBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.glassBorder),
            ),
            child: _buildAnswerWidget(q, type, qId, isSubmitting, context),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerWidget(Map<String, dynamic> q, String type, String qId, bool isSubmitting, BuildContext context) {
    if (type == 'SHORT_ANSWER') {
      return TextField(
        controller: textControllers[qId],
        enabled: !isSubmitting,
        style: TextStyle(color: context.textColor),
        decoration: InputDecoration(
          hintText: 'Type your answer here...',
          hintStyle:  TextStyle(color: context.textColor54.withOpacity(0.5)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.glassBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.glassBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1))),
          filled: true,
          fillColor: context.isDark ? const Color(0xFF0F172A) : Colors.white,
        ),
        maxLines: 5,
        onChanged: (val) => onAnswerChanged(qId, val),
      );
    }

    if (type == 'MCQ_SINGLE' || type == 'TRUE_FALSE') {
      final options = type == 'TRUE_FALSE' ? ['True', 'False'] : List<String>.from(q['options'] ?? []);
      return Column(
        children: options.asMap().entries.map((e) {
          final opt = e.value;
          final selected = (answers[qId] as String?) == opt;
          return GestureDetector(
            onTap: isSubmitting ? null : () => onAnswerChanged(qId, opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF6366F1).withOpacity(0.2) : context.glassBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? const Color(0xFF6366F1) : context.glassBorder, width: selected ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? const Color(0xFF6366F1) : Colors.transparent,
                      border: Border.all(color: selected ? const Color(0xFF6366F1) : Colors.white38, width: 2),
                    ),
                    child: selected ? Icon(Icons.check, color: context.textColor, size: 14) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(opt, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontSize: 15))),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    if (type == 'MCQ_MULTI') {
      final options = List<String>.from(q['options'] ?? []);
      final selected = List<String>.from(answers[qId] ?? []);
      return Column(
        children: options.map((opt) {
          final isChecked = selected.contains(opt);
          return GestureDetector(
            onTap: isSubmitting ? null : () {
              final updated = List<String>.from(selected);
              if (isChecked) { updated.remove(opt); } else { updated.add(opt); }
              onAnswerChanged(qId, updated);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isChecked ? const Color(0xFF6366F1).withOpacity(0.2) : context.glassBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isChecked ? const Color(0xFF6366F1) : context.glassBorder, width: isChecked ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: isChecked ? const Color(0xFF6366F1) : Colors.transparent,
                      border: Border.all(color: isChecked ? const Color(0xFF6366F1) : Colors.white38, width: 2),
                    ),
                    child: isChecked ? Icon(Icons.check, color: context.textColor, size: 14) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(opt, style: TextStyle(color: isChecked ? Colors.white : Colors.white70, fontSize: 15))),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    return const Text('Unknown question type', style: TextStyle(color: Colors.redAccent));
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  // Ignore lint — used in build context indirectly
  // ignore: unused_field
  Map<String, dynamic> get _answers => answers;

  String _typeLabel(String type) {
    switch (type) {
      case 'MCQ_SINGLE': return 'Single Choice';
      case 'MCQ_MULTI': return 'Multi Choice';
      case 'TRUE_FALSE': return 'True / False';
      case 'SHORT_ANSWER': return 'Short Answer';
      default: return type;
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  WIDGET 4: Footer — Prev | Submit | Next (always visible)
// ─────────────────────────────────────────────────────────────
class _ExamFooter extends StatelessWidget {
  final int currentIndex;
  final int total;
  final bool isSubmitting;
  final bool canSubmit;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  const _ExamFooter({
    required this.currentIndex, required this.total, required this.isSubmitting,
    required this.canSubmit, required this.onPrev, required this.onNext, required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final isFirst = currentIndex == 0;
    final isLast = currentIndex == total - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(top: BorderSide(color: context.glassBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Previous (always shown, disabled on first) ──
          IconButton(
            onPressed: isFirst || isSubmitting ? null : onPrev,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: isFirst ? context.glassBorder : Colors.white70,
            ),
            style: IconButton.styleFrom(
              backgroundColor: isFirst
                  ? context.glassBg
                  : context.glassBorder,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(12),
            ),
          ),

          // ── Submit (always centered) ──
          ElevatedButton.icon(
            onPressed: isSubmitting || !canSubmit ? null : onSubmit,
            icon: isSubmitting
                ? SizedBox(
                    width: 16, height: 16,
                    child: JyamitiLoader(strokeWidth: 2, color: context.textColor),
                  )
                : Transform.rotate(
                    angle: -90 * 3.1415927 / 180,
                    child: Icon(Icons.send_rounded, color: context.textColor, size: 18),
                  ),
            label: Text(
              isSubmitting ? 'Submitting...' : (canSubmit ? 'Submit' : 'Not yet...'),
              style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: canSubmit && !isSubmitting
                  ? const Color(0xFF10B981)
                  : Colors.grey.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              elevation: 0,
            ),
          ),

          // ── Next (always shown, disabled on last) ──
          IconButton(
            onPressed: isLast || isSubmitting ? null : onNext,
            icon: Icon(
              Icons.arrow_forward_rounded,
              color: isLast ? context.glassBorder : const Color(0xFF6366F1),
            ),
            style: IconButton.styleFrom(
              backgroundColor: isLast
                  ? context.glassBg
                  : const Color(0xFF6366F1).withOpacity(0.15),
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}
