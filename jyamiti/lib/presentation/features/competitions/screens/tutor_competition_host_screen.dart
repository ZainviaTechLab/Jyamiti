import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../services/competition_service.dart';
import '../../../../services/api_service.dart';
import '../../../../widgets/latex_rich_text.dart';
import 'competition_analytics_dashboard_screen.dart';

// ==========================================
// MATH FUNDAMENTALS (99math-style arithmetic drills) generation
// ==========================================
// Kept file-scoped (not instance methods) since none of this needs
// context/setState -- it's pure number generation shared by the live
// "Example Problems" preview and the actual questions sent at creation.

class _NumRange {
  final num min;
  final num max;
  const _NumRange(this.min, this.max);
}

/// Preset range chips, in display order. Keys double as their labels.
const Map<String, _NumRange> kMathFundamentalsRangePresets = {
  '1...10': _NumRange(1, 10),
  '1...20': _NumRange(1, 20),
  '10...20': _NumRange(10, 20),
  '20...100': _NumRange(20, 100),
  '100...1000': _NumRange(100, 1000),
};

class MathFundamentalsProblem {
  final num a;
  final num b;
  final num answer;
  final String text;
  MathFundamentalsProblem(this.a, this.b)
      : answer = a + b,
        text = '${formatMathNumber(a)} + ${formatMathNumber(b)}';
}

/// Renders a number the way a student should see it: whole numbers with no
/// trailing ".0", decimals trimmed of trailing zeros (18.50 -> "18.5").
String formatMathNumber(num n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  var s = n.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s;
}

final Random _mathFundamentalsRandom = Random();

num _randomNumberInRanges(
  List<_NumRange> ranges, {
  required bool isDecimal,
  int? multipleOf,
}) {
  final range = ranges[_mathFundamentalsRandom.nextInt(ranges.length)];
  if (multipleOf != null && multipleOf > 1) {
    final lo = (range.min / multipleOf).ceil();
    final hi = (range.max / multipleOf).floor();
    if (hi < lo) return (range.min / multipleOf).round() * multipleOf;
    return (lo + _mathFundamentalsRandom.nextInt(hi - lo + 1)) * multipleOf;
  }
  if (isDecimal) {
    final v = range.min + _mathFundamentalsRandom.nextDouble() * (range.max - range.min);
    return double.parse(v.toStringAsFixed(1));
  }
  final lo = range.min.round();
  final hi = range.max.round();
  if (hi <= lo) return lo;
  return lo + _mathFundamentalsRandom.nextInt(hi - lo + 1);
}

MathFundamentalsProblem generateAdditionProblem({
  required List<_NumRange> ranges,
  required bool isDecimal,
  int? multipleOf,
}) {
  final a = _randomNumberInRanges(ranges, isDecimal: isDecimal, multipleOf: multipleOf);
  final b = _randomNumberInRanges(ranges, isDecimal: isDecimal, multipleOf: multipleOf);
  return MathFundamentalsProblem(a, b);
}

class TutorCompetitionHostScreen extends StatefulWidget {
  final Map<String, dynamic> batch;
  final bool isInline;
  final VoidCallback? onBack;

  const TutorCompetitionHostScreen({
    super.key,
    required this.batch,
    this.isInline = false,
    this.onBack,
  });

  @override
  State<TutorCompetitionHostScreen> createState() =>
      _TutorCompetitionHostScreenState();
}

class _TutorCompetitionHostScreenState
    extends State<TutorCompetitionHostScreen> {
  bool _isLoading = false;
  String _errorMessage = '';

  // Host Game State
  Map<String, dynamic>? _competition;
  String? _roomCode;
  String _gameState = 'CREATE'; // 'CREATE' | 'LOBBY' | 'HOST_QUESTION' | 'HOST_ROUND_RESULT' | 'FINISHED'
  List<dynamic> _participants = [];
  int _currentRoundIndex = 0;
  int _answeredCount = 0;
  List<dynamic> _roundLeaderboard = [];
  Timer? _pollTimer;

  // Creation Form Controllers
  final TextEditingController _titleCtrl = TextEditingController();
  int _grade = 10;
  int _numberOfRounds = 3; // Options: 3, 5
  int _roundDurationMinutes = 1; // Options: 1, 2, 3, 5

  // Curriculum Chapter & Topic Filter State
  List<Map<String, dynamic>> _chapters = [];
  Set<String> _selectedChapters = {};
  Set<String> _selectedTopics = {};
  bool _isLoadingTopics = true;

  // Math Fundamentals creation mode (99math-style arithmetic drills), an
  // alternative to picking questions from the course syllabus above.
  String _creationMode = 'SYLLABUS'; // 'SYLLABUS' | 'MATH_FUNDAMENTALS'
  String _mfOperation = 'addition'; // only addition is implemented so far
  String _mfSubtopic = 'integers'; // 'integers' | 'decimals'
  String _mfSelectedPreset = '1...20';
  bool _mfShowCustomize = false;
  final List<_NumRange> _mfCustomRanges = [const _NumRange(1, 20)];
  int? _mfMultipleOf; // null | 10 | 100 | 1000
  MathFundamentalsProblem? _mfExampleProblem;

  List<_NumRange> _mfEffectiveRanges() {
    if (_mfShowCustomize) {
      final valid = _mfCustomRanges.where((r) => r.max >= r.min).toList();
      if (valid.isNotEmpty) return valid;
    }
    return [kMathFundamentalsRangePresets[_mfSelectedPreset] ?? const _NumRange(1, 20)];
  }

  /// Mutates _mfExampleProblem only -- callers already inside a setState
  /// (e.g. a config chip's onTap) call this directly; _refreshExample
  /// below wraps it in its own setState for standalone callers (the
  /// "Show more" button).
  void _regenerateExampleProblem() {
    _mfExampleProblem = generateAdditionProblem(
      ranges: _mfEffectiveRanges(),
      isDecimal: _mfSubtopic == 'decimals',
      multipleOf: _mfMultipleOf,
    );
  }

  void _refreshExampleProblem() {
    setState(_regenerateExampleProblem);
  }

  List<String> get _availableTopicsForSelectedChapters {
    final Set<String> available = {};
    for (var chap in _chapters) {
      if (_selectedChapters.contains(chap['title'])) {
        final List<dynamic> tList = chap['topics'] ?? [];
        for (var t in tList) {
          available.add(t.toString());
        }
      }
    }
    final result = available.toList()..sort();
    return result;
  }

  @override
  void initState() {
    super.initState();
    CompetitionService.initSocket(ApiService.baseUrl);
    _setupSocketListeners();
    _titleCtrl.text = '${widget.batch['name'] ?? 'Batch'} Speed Arena';
    _grade = widget.batch['grade'] != null
        ? (int.tryParse(widget.batch['grade'].toString().replaceAll(RegExp(r'\D'), '')) ?? 10)
        : 10;
    _loadBatchTopics();
    _regenerateExampleProblem();
  }

  // Timer & Racetrack State
  int _overallTimerSeconds = 0;
  Timer? _gameDurationTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _gameDurationTimer?.cancel();
    _titleCtrl.dispose();
    super.dispose();
  }

  List<dynamic> _cleanParticipants(List<dynamic> list) {
    final tutorId = (_competition?['tutorId'] is Map
            ? _competition?['tutorId']?['_id']
            : _competition?['tutorId'])
        ?.toString();
    return list.where((p) {
      final uId = p['userId']?.toString();
      final name = p['name']?.toString();
      if (tutorId != null && uId == tutorId) return false;
      if (name == 'Tutor Host') return false;
      return true;
    }).toList();
  }

  void _setupSocketListeners() {
    final socket = CompetitionService.socket;
    if (socket == null) {
      Future.delayed(const Duration(milliseconds: 500), _setupSocketListeners);
      return;
    }

    socket.on('competition:player_joined', (data) {
      if (mounted) {
        setState(() {
          _participants = _cleanParticipants(data['participants'] ?? []);
        });
      }
    });

    socket.on('competition:player_progress', (data) {
      if (mounted && data['participants'] != null) {
        setState(() {
          _participants = _cleanParticipants(data['participants']);
        });
      }
    });

    socket.on('competition:answer_submitted', (data) {
      if (mounted) {
        setState(() {
          _answeredCount = data['answeredCount'] ?? _answeredCount;
          if (data['totalParticipants'] != null && _participants.length < data['totalParticipants']) {
            _refreshParticipants();
          }
        });
      }
    });

    socket.on('competition:round_ended', (data) {
      if (mounted) {
        setState(() {
          _gameState = 'HOST_ROUND_RESULT';
          _roundLeaderboard = _cleanParticipants(data['leaderboard'] ?? []);
        });
      }
    });

    socket.on('competition:game_over', (data) {
      if (mounted) {
        setState(() {
          _gameState = 'FINISHED';
        });
      }
    });
  }

  Future<void> _refreshParticipants() async {
    if (_roomCode == null) return;
    try {
      final res = await CompetitionService.getRoomByCode(_roomCode!);
      if (mounted && res['competition'] != null) {
        setState(() {
          _participants = _cleanParticipants(res['competition']['participants'] ?? []);
        });
      }
    } catch (_) {}
  }

  void _startLobbyPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_gameState == 'LOBBY') {
        _refreshParticipants();
      } else {
        _pollTimer?.cancel();
      }
    });
  }

  Future<void> _loadBatchTopics() async {
    try {
      final batchId = widget.batch['id'] ?? widget.batch['_id'];
      final res = await CompetitionService.getBatchTopics(batchId.toString());
      if (mounted) {
        final List<dynamic> rawChapters = res['chapters'] ?? [];
        final List<Map<String, dynamic>> parsedChapters = [];
        final Set<String> allChapTitles = {};
        final Set<String> allTopicTitles = {};

        for (var c in rawChapters) {
          final title = c['title']?.toString() ?? 'Chapter';
          final List<dynamic> tList = c['topics'] ?? [];
          final topics = tList.map((e) => e.toString()).toList();
          parsedChapters.add({
            'title': title,
            'topics': topics,
          });
          allChapTitles.add(title);
          allTopicTitles.addAll(topics);
        }

        setState(() {
          _chapters = parsedChapters;
          _selectedChapters = Set.from(allChapTitles);
          _selectedTopics = Set.from(allTopicTitles);
          _isLoadingTopics = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingTopics = false;
        });
      }
    }
  }

  Future<void> _createCompetitionRoom() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final batchId = widget.batch['id'] ?? widget.batch['_id'];

      // Math Fundamentals questions are generated right here (client-side)
      // rather than resolved server-side from selectedTopics -- there's no
      // question bank to look up, just the tutor's chosen operation/range.
      List<Map<String, dynamic>> generatedQuestions = [];
      if (_creationMode == 'MATH_FUNDAMENTALS') {
        final ranges = _mfEffectiveRanges();
        final isDecimal = _mfSubtopic == 'decimals';
        final subtopicLabel = 'Addition (${isDecimal ? 'Decimals' : 'Integers'})';
        for (int i = 0; i < _numberOfRounds; i++) {
          final problem = generateAdditionProblem(
            ranges: ranges,
            isDecimal: isDecimal,
            multipleOf: _mfMultipleOf,
          );
          generatedQuestions.add({
            'id': 'mf_${DateTime.now().millisecondsSinceEpoch}_$i',
            'text': problem.text,
            'answerType': 'NUMERIC',
            'correctAnswer': formatMathNumber(problem.answer),
            'category': 'Math Fundamentals',
            'subtopic': subtopicLabel,
            'points': 1000,
          });
        }
      }

      final res = await CompetitionService.createCompetition(
        title: title,
        batchId: batchId.toString(),
        grade: _grade,
        numberOfRounds: _numberOfRounds,
        roundDurationMinutes: _roundDurationMinutes,
        selectedTopics: _creationMode == 'SYLLABUS' ? _selectedTopics.toList() : [],
        // Auto-populated server-side from selectedTopics for SYLLABUS mode
        // (empty list); pre-generated above for MATH_FUNDAMENTALS.
        questions: generatedQuestions,
        mode: _creationMode,
      );

      final created = res['competition'];
      _roomCode = created['roomCode'];
      _competition = created;

      CompetitionService.joinAsHost(
        roomCode: _roomCode!,
      );

      _setupSocketListeners();
      _startLobbyPolling();

      setState(() {
        _gameState = 'LOBBY';
        _participants = _cleanParticipants(created['participants'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _startGame() {
    if (_roomCode == null) return;
    CompetitionService.startGame(_roomCode!);

    final durationMins = _roundDurationMinutes > 0 ? _roundDurationMinutes : 1;
    final int roundSecs = (durationMins * 60).toInt();

    setState(() {
      _gameState = 'HOST_QUESTION';
      _currentRoundIndex = 0;
      _answeredCount = 0;
      _overallTimerSeconds = roundSecs;
    });

    _gameDurationTimer?.cancel();
    _gameDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_overallTimerSeconds <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _overallTimerSeconds = 0;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _overallTimerSeconds -= 1;
          });
        }
      }
    });
  }

  void _endRound() {
    if (_roomCode == null) return;
    _gameDurationTimer?.cancel();
    CompetitionService.endRound(_roomCode!);
    setState(() {
      _gameState = 'HOST_ROUND_RESULT';
    });
  }

  void _nextRound() {
    if (_roomCode == null) return;
    CompetitionService.nextRound(_roomCode!);
    final durationMins = _roundDurationMinutes > 0 ? _roundDurationMinutes : 1;
    final int roundSecs = (durationMins * 60).toInt();

    setState(() {
      _gameState = 'HOST_QUESTION';
      _currentRoundIndex += 1;
      _answeredCount = 0;
      _overallTimerSeconds = roundSecs;
    });

    _gameDurationTimer?.cancel();
    _gameDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_overallTimerSeconds <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _overallTimerSeconds = 0;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _overallTimerSeconds -= 1;
          });
        }
      }
    });
  }

  void _endGame() {
    if (_roomCode == null) return;
    CompetitionService.endGame(_roomCode!);
    if (_competition != null && _competition!['_id'] != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CompetitionAnalyticsDashboardScreen(
            competitionId: _competition!['_id'],
            isInline: widget.isInline,
            onBack: widget.onBack,
          ),
        ),
      );
    }
  }

  Widget _buildCreateState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.sports_esports_rounded,
                      color: Color(0xFF6366F1),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Host Live Arena Competition',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Batch: ${widget.batch['name']}',
                          style: TextStyle(
                            color: context.textColor60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Title Field
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Competition Title',
                  labelStyle: TextStyle(color: context.textColor60, fontSize: 13),
                  filled: true,
                  fillColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                style: TextStyle(color: context.textColor),
              ),
              const SizedBox(height: 16),

              // Question Source: pull from the course syllabus, or
              // procedurally-generated arithmetic drills (Math Fundamentals)
              _buildCreationModeSwitch(),
              const SizedBox(height: 20),

              if (_creationMode == 'SYLLABUS') ...[
              // Step 1: Select Chapter(s)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '1. Select Chapter(s) (${_selectedChapters.length}/${_chapters.length})',
                    style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _chapters.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  _selectedChapters = Set.from(_chapters.map((c) => c['title']));
                                  _selectedTopics = Set.from(_availableTopicsForSelectedChapters);
                                });
                              },
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 24)),
                        child: const Text('Select All', style: TextStyle(fontSize: 11, color: Color(0xFF6366F1))),
                      ),
                      TextButton(
                        onPressed: _chapters.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  _selectedChapters.clear();
                                  _selectedTopics.clear();
                                });
                              },
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 24)),
                        child: Text('Clear All', style: TextStyle(fontSize: 11, color: context.textColor60)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _isLoadingTopics
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Center(child: JyamitiLoader(strokeWidth: 2)),
                    )
                  : _chapters.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Questions will be fetched across all course syllabus topics.',
                            style: TextStyle(color: context.textColor60, fontSize: 12),
                          ),
                        )
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 140),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.glassBorder),
                          ),
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: _chapters.map((chap) {
                                final chapTitle = chap['title'].toString();
                                final isSelected = _selectedChapters.contains(chapTitle);
                                return FilterChip(
                                  avatar: Icon(
                                    isSelected ? Icons.folder_open_rounded : Icons.folder_outlined,
                                    size: 16,
                                    color: isSelected ? Colors.white : const Color(0xFF6366F1),
                                  ),
                                  label: Text(
                                    chapTitle,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : context.textColor,
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedChapters.add(chapTitle);
                                        // Auto-select topics in newly selected chapter
                                        final List<dynamic> tList = chap['topics'] ?? [];
                                        for (var t in tList) {
                                          _selectedTopics.add(t.toString());
                                        }
                                      } else {
                                        _selectedChapters.remove(chapTitle);
                                        // Remove topics belonging strictly to removed chapter
                                        final List<dynamic> tList = chap['topics'] ?? [];
                                        for (var t in tList) {
                                          _selectedTopics.remove(t.toString());
                                        }
                                      }
                                    });
                                  },
                                  selectedColor: const Color(0xFF6366F1),
                                  backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                                  checkmarkColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(
                                      color: isSelected ? const Color(0xFF6366F1) : context.glassBorder,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
              const SizedBox(height: 16),

              // Step 2: Select Topic(s) inside Selected Chapter(s)
              if (_selectedChapters.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '2. Select Topics in Selected Chapter(s) (${_selectedTopics.length}/${_availableTopicsForSelectedChapters.length})',
                        style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _availableTopicsForSelectedChapters.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    _selectedTopics = Set.from(_availableTopicsForSelectedChapters);
                                  });
                                },
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 24)),
                          child: const Text('Select All', style: TextStyle(fontSize: 11, color: Color(0xFF6366F1))),
                        ),
                        TextButton(
                          onPressed: _availableTopicsForSelectedChapters.isEmpty
                              ? null
                              : () => setState(() => _selectedTopics.clear()),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 24)),
                          child: Text('Clear All', style: TextStyle(fontSize: 11, color: context.textColor60)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.glassBorder),
                  ),
                  child: _availableTopicsForSelectedChapters.isEmpty
                      ? Center(
                          child: Text(
                            'No sub-topics available for selected chapter(s).',
                            style: TextStyle(color: context.textColor60, fontSize: 12),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: _availableTopicsForSelectedChapters.map((topic) {
                              final isSelected = _selectedTopics.contains(topic);
                              return FilterChip(
                                label: Text(
                                  topic,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : context.textColor,
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedTopics.add(topic);
                                    } else {
                                      _selectedTopics.remove(topic);
                                    }
                                  });
                                },
                                selectedColor: const Color(0xFF8B5CF6),
                                backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                                checkmarkColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: isSelected ? const Color(0xFF8B5CF6) : context.glassBorder,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
              ],
              ] else ...[
                _buildMathFundamentalsConfig(),
              ],
              const SizedBox(height: 16),

              // Number of Rounds Picker (3 / 5)
              Text(
                'Number of Rounds',
                style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [3, 5].map((rounds) {
                  final isSelected = _numberOfRounds == rounds;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _numberOfRounds = rounds),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6366F1)
                              : (context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF6366F1) : context.glassBorder,
                          ),
                        ),
                        child: Text(
                          '$rounds Rounds',
                          style: TextStyle(
                            color: isSelected ? Colors.white : context.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Round Duration Picker (1 / 2 / 3 / 5 minutes)
              Text(
                'Round Duration',
                style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [1, 2, 3, 5].map((mins) {
                  final isSelected = _roundDurationMinutes == mins;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _roundDurationMinutes = mins),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6366F1)
                              : (context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF6366F1) : context.glassBorder,
                          ),
                        ),
                        child: Text(
                          '$mins min',
                          style: TextStyle(
                            color: isSelected ? Colors.white : context.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_errorMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _createCompetitionRoom,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: JyamitiLoader(strokeWidth: 2))
                      : const Icon(Icons.rocket_launch_rounded),
                  label: Text(
                    _isLoading ? 'GENERATING ROOM...' : 'CREATE ARENA ROOM',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Math Fundamentals creation UI
  // ---------------------------------------------------------------------

  Widget _buildCreationModeSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeTab('SYLLABUS', 'From Syllabus', Icons.menu_book_rounded),
          ),
          Expanded(
            child: _modeTab(
              'MATH_FUNDAMENTALS',
              'Math Fundamentals',
              Icons.calculate_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTab(String mode, String label, IconData icon) {
    final isSelected = _creationMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _creationMode = mode;
        _regenerateExampleProblem();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : context.textColor60),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : context.textColor60,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 13),
    );
  }

  Widget _buildMathFundamentalsConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Operation'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _operationChip('addition', 'Addition', Icons.add_rounded, enabled: true),
            _operationChip('subtraction', 'Subtraction', Icons.remove_rounded, enabled: false),
            _operationChip('multiplication', 'Multiplication', Icons.close_rounded, enabled: false),
            _operationChip('division', 'Division', Icons.percent_rounded, enabled: false),
          ],
        ),
        const SizedBox(height: 20),

        _sectionLabel('Subtopic'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _toggleButton('Integers', _mfSubtopic == 'integers', () {
                setState(() {
                  _mfSubtopic = 'integers';
                  _regenerateExampleProblem();
                });
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toggleButton('Decimals', _mfSubtopic == 'decimals', () {
                setState(() {
                  _mfSubtopic = 'decimals';
                  _regenerateExampleProblem();
                });
              }),
            ),
          ],
        ),
        const SizedBox(height: 20),

        _sectionLabel('Number Range'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...kMathFundamentalsRangePresets.keys.map((label) {
              final isSelected = !_mfShowCustomize && _mfSelectedPreset == label;
              return _rangeChip(label, isSelected, () {
                setState(() {
                  _mfSelectedPreset = label;
                  _mfShowCustomize = false;
                  _regenerateExampleProblem();
                });
              });
            }),
            _rangeChip(
              'Customize',
              _mfShowCustomize,
              () {
                setState(() {
                  _mfShowCustomize = !_mfShowCustomize;
                  _regenerateExampleProblem();
                });
              },
              icon: _mfShowCustomize ? Icons.close_rounded : Icons.tune_rounded,
            ),
          ],
        ),

        if (_mfShowCustomize) ...[
          const SizedBox(height: 16),
          _buildCustomRangeEditor(),
        ],

        const SizedBox(height: 20),
        _sectionLabel('Example Problems'),
        const SizedBox(height: 8),
        _buildExamplePreview(),
      ],
    );
  }

  Widget _operationChip(String key, String label, IconData icon, {required bool enabled}) {
    final isSelected = enabled && _mfOperation == key;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: enabled
            ? () => setState(() {
                  _mfOperation = key;
                  _regenerateExampleProblem();
                })
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF6366F1)
                : (context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF6366F1) : context.glassBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? Colors.white : context.textColor70),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : context.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (!enabled) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.textColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Soon',
                    style: TextStyle(
                      color: context.textColor60,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B)
              : (context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : context.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : context.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _rangeChip(String label, bool isSelected, VoidCallback onTap, {IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B)
              : (context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFF59E0B) : context.glassBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: isSelected ? Colors.white : context.textColor70),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : context.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomRangeEditor() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose custom range(s)',
            style: TextStyle(color: context.textColor70, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < _mfCustomRanges.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: _rangeBoundField(_mfCustomRanges[i].min, (v) {
                      setState(() {
                        _mfCustomRanges[i] = _NumRange(v, _mfCustomRanges[i].max);
                        _regenerateExampleProblem();
                      });
                    }),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('to', style: TextStyle(color: context.textColor60, fontSize: 12)),
                  ),
                  Expanded(
                    child: _rangeBoundField(_mfCustomRanges[i].max, (v) {
                      setState(() {
                        _mfCustomRanges[i] = _NumRange(_mfCustomRanges[i].min, v);
                        _regenerateExampleProblem();
                      });
                    }),
                  ),
                  if (_mfCustomRanges.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                      tooltip: 'Remove range',
                      onPressed: () => setState(() {
                        _mfCustomRanges.removeAt(i);
                        _regenerateExampleProblem();
                      }),
                    ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () => setState(() {
              _mfCustomRanges.add(const _NumRange(1, 20));
            }),
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Add another range'),
          ),
          const SizedBox(height: 8),
          Text(
            'Whole tens, hundreds and thousands',
            style: TextStyle(color: context.textColor70, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _multipleChip('x10', 10),
              _multipleChip('x100', 100),
              _multipleChip('x1000', 1000),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rangeBoundField(num value, ValueChanged<num> onChanged) {
    return TextFormField(
      initialValue: formatMathNumber(value),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        filled: true,
        fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.glassBorder),
        ),
      ),
      onChanged: (v) {
        final parsed = num.tryParse(v);
        if (parsed != null) onChanged(parsed);
      },
    );
  }

  Widget _multipleChip(String label, int multiplier) {
    final isSelected = _mfMultipleOf == multiplier;
    return GestureDetector(
      onTap: () => setState(() {
        _mfMultipleOf = isSelected ? null : multiplier;
        _regenerateExampleProblem();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1)
              : (context.isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF6366F1) : context.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : context.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildExamplePreview() {
    final problem = _mfExampleProblem;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              problem?.text ?? 'Adjust settings to preview a problem',
              style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ),
          TextButton.icon(
            onPressed: _refreshExampleProblem,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Show more'),
          ),
        ],
      ),
    );
  }

  Widget _buildLobbyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text('SHARE THIS ROOM CODE WITH STUDENTS', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _roomCode ?? 'JYAM-0000',
                      style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 3),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: Colors.white),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _roomCode ?? ''));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room code copied!')));
                      },
                      tooltip: 'Copy Code',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('Connected Students (${_participants.length})', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: context.textColor60, size: 20),
                    onPressed: _refreshParticipants,
                    tooltip: 'Refresh connected list',
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _startGame,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('START GAME NOW', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _participants.length,
            itemBuilder: (context, idx) {
              final p = _participants[idx];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.glassBorder),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF6366F1),
                      radius: 12,
                      child: Text((p['name'] ?? 'S')[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p['name'] ?? 'Student',
                        style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHostQuestionState() {
    final List<dynamic> questions = _competition?['questions'] ?? [];
    final totalRounds = _numberOfRounds > 0 ? _numberOfRounds : (questions.isNotEmpty ? questions.length : 3);

    // Sort participants by score descending for live leaderboard positions
    final sortedList = List<dynamic>.from(_participants);
    sortedList.sort((a, b) {
      final scoreA = (a['totalScore'] ?? 0) as int;
      final scoreB = (b['totalScore'] ?? 0) as int;
      return scoreB.compareTo(scoreA);
    });

    final finishedCount = sortedList.where((p) => p['isFinished'] == true || (p['roundsCompleted'] ?? 0) >= totalRounds).length;
    final mins = _overallTimerSeconds ~/ 60;
    final secs = _overallTimerSeconds % 60;
    final formattedTime = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Overall Game Countdown Timer Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.directions_car_rounded, color: Colors.amberAccent, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'LIVE ARENA RACE TRACK',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Completed: $finishedCount / ${sortedList.length} Students | Total Rounds: $totalRounds',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.amberAccent, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        formattedTime,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Race Track Lanes Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🏎️ Live Student Speed & Progress',
                style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '⚡ REAL-TIME SYNC',
                  style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Race Lanes List
          if (sortedList.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.glassBorder),
              ),
              child: Text(
                'Waiting for students to start answering...',
                style: TextStyle(color: context.textColor60, fontSize: 14),
              ),
            )
          else
            ...List.generate(sortedList.length, (index) {
              final p = sortedList[index];
              final String name = p['name'] ?? 'Student';
              final int score = p['totalScore'] ?? 0;
              final int streak = p['streak'] ?? 0;
              final int roundsComp = p['roundsCompleted'] ?? 0;
              final double avgSpeed = (p['avgSpeedSec'] ?? 0.0).toDouble();
              final double rawPct = (p['progressPct'] ?? (totalRounds > 0 ? (roundsComp / totalRounds) : 0.0)).toDouble();
              final double progressPct = rawPct.clamp(0.0, 1.0);
              final bool isFinished = p['isFinished'] == true || roundsComp >= totalRounds;

              final String rankBadge = index == 0
                  ? '🥇'
                  : (index == 1 ? '🥈' : (index == 2 ? '🥉' : '#${index + 1}'));

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isFinished
                        ? const Color(0xFF10B981)
                        : (index == 0 ? const Color(0xFFF59E0B) : context.glassBorder),
                    width: isFinished || index == 0 ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Lane Header Info
                    Row(
                      children: [
                        Text(rankBadge, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: const Color(0xFF6366F1),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'S',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                name,
                                style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              if (streak >= 2) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '🔥 ${streak}x',
                                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Speed Indicator Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.bolt_rounded, color: Color(0xFF3B82F6), size: 14),
                              const SizedBox(width: 2),
                              Text(
                                avgSpeed > 0 ? '${avgSpeed.toStringAsFixed(1)}s/Q' : '--',
                                style: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Score
                        Text(
                          '$score pts',
                          style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Race Track Animation Line
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final trackWidth = constraints.maxWidth;
                        const carWidth = 32.0;
                        final maxCarOffset = trackWidth - carWidth;
                        final currentCarPosition = progressPct * maxCarOffset;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.centerLeft,
                              children: [
                                // Background Track Line
                                Container(
                                  height: 12,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                // Filled Progress Track
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOutCubic,
                                  height: 12,
                                  width: trackWidth * progressPct,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isFinished
                                          ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                          : [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                // Moving Racer Icon
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOutCubic,
                                  left: currentCarPosition,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: isFinished ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: (isFinished ? const Color(0xFF10B981) : const Color(0xFF6366F1)).withOpacity(0.5),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: const Text('🏎️', style: TextStyle(fontSize: 14)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('START 🚩', style: TextStyle(fontSize: 10, color: context.textColor60, fontWeight: FontWeight.bold)),
                                Text(
                                  isFinished ? '🏁 FINISHED ($roundsComp/$totalRounds)' : 'Round $roundsComp of $totalRounds',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isFinished ? const Color(0xFF10B981) : context.textColor60,
                                    fontWeight: isFinished ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                Text('FINISH 🏁', style: TextStyle(fontSize: 10, color: context.textColor60, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _endRound,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 4,
                  ),
                  icon: const Icon(Icons.leaderboard_rounded),
                  label: Text(
                    'END ROUND ${_currentRoundIndex + 1} & VIEW LEADERBOARD ➔',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Button to view Full Analytics Dashboard
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final compId = _competition?['_id'] ?? _competition?['id'] ?? _roomCode;
                if (compId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CompetitionAnalyticsDashboardScreen(competitionId: compId.toString()),
                    ),
                  );
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6366F1),
                side: const BorderSide(color: Color(0xFF6366F1)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.analytics_rounded),
              label: const Text('VIEW LIVE BATCH ANALYTICS & WEAK POINTS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostRoundResultState() {
    final List<dynamic> questions = _competition?['questions'] ?? [];
    final bool isLastRound = _currentRoundIndex >= (questions.length - 1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text('Round ${_currentRoundIndex + 1} Leaderboard', style: TextStyle(color: context.textColor, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.glassBorder),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _roundLeaderboard.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final p = _roundLeaderboard[idx];
                return ListTile(
                  leading: CircleAvatar(backgroundColor: const Color(0xFF6366F1), radius: 12, child: Text('#${p['rank']}', style: const TextStyle(fontSize: 10, color: Colors.white))),
                  title: Text(p['name'] ?? 'Student', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
                  trailing: Text('${p['totalScore']} pts', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isLastRound ? _endGame : _nextRound,
                  style: ElevatedButton.styleFrom(backgroundColor: isLastRound ? const Color(0xFF10B981) : const Color(0xFF6366F1), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: Icon(isLastRound ? Icons.flag_rounded : Icons.arrow_forward_rounded),
                  label: Text(isLastRound ? 'FINISH COMPETITION & ANALYZE' : 'NEXT ROUND ➔', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('ARENA HOST CONTROL', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 16)),
        centerTitle: true,
        leading: widget.isInline
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack ?? () => Navigator.maybePop(context),
                tooltip: 'Back',
              )
            : null,
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 1,
        iconTheme: IconThemeData(color: context.textColor),
      ),
      body: _gameState == 'CREATE'
          ? _buildCreateState()
          : _gameState == 'LOBBY'
              ? _buildLobbyState()
              : _gameState == 'HOST_QUESTION'
                  ? _buildHostQuestionState()
                  : _buildHostRoundResultState(),
    );
  }
}
