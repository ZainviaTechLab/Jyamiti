import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:jyamiti/providers/auth_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../services/competition_service.dart';
import '../../../../services/api_service.dart';
import '../../../../widgets/latex_rich_text.dart';

class StudentCompetitionGameScreen extends StatefulWidget {
  final String? initialRoomCode;
  final bool isInline;
  final VoidCallback? onBack;

  const StudentCompetitionGameScreen({
    super.key,
    this.initialRoomCode,
    this.isInline = false,
    this.onBack,
  });

  @override
  State<StudentCompetitionGameScreen> createState() =>
      _StudentCompetitionGameScreenState();
}

class _StudentCompetitionGameScreenState
    extends State<StudentCompetitionGameScreen> {
  final TextEditingController _codeCtrl = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';

  // Game Room State
  String? _roomCode;
  String _gameState = 'JOIN'; // 'JOIN' | 'LOBBY' | 'QUESTION' | 'ROUND_RESULT' | 'GAME_OVER'
  List<dynamic> _participants = [];
  List<dynamic>? _allQuestions;
  Map<String, dynamic>? _currentQuestion;
  int _currentRoundIndex = 0;
  int _totalRounds = 0;
  int _timePerQuestion = 30;

  // Question Timer State
  Timer? _countdownTimer;
  Timer? _waitingPollTimer;
  int _secondsRemaining = 30;
  int _timeTakenSec = 0;

  // Student Response State
  int? _selectedOptionIndex;
  bool _answerSubmitted = false;
  int _correctOptionIndex = 0;
  String _explanation = '';
  List<dynamic> _roundLeaderboard = [];
  List<dynamic> _finalPodium = [];

  // Math Fundamentals (NUMERIC answerType) free-response input
  final TextEditingController _numericAnswerCtrl = TextEditingController();
  bool get _isNumericQuestion {
    final type = _currentQuestion?['answerType']?.toString().toUpperCase();
    final List<dynamic> options = _currentQuestion?['options'] ?? [];
    return type == 'NUMERIC' || options.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    CompetitionService.initSocket(ApiService.baseUrl);
    _setupSocketListeners();

    if (widget.initialRoomCode != null && widget.initialRoomCode!.isNotEmpty) {
      _codeCtrl.text = widget.initialRoomCode!;
      _joinRoom();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _waitingPollTimer?.cancel();
    if (_roomCode != null) {
      CompetitionService.leaveRoom(_roomCode!);
    }
    _codeCtrl.dispose();
    _numericAnswerCtrl.dispose();
    super.dispose();
  }

  List<dynamic> _cleanParticipants(List<dynamic> list) {
    return list.where((p) {
      final name = p['name']?.toString();
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

    socket.on('competition:round_started', (data) {
      _waitingPollTimer?.cancel();
      _countdownTimer?.cancel();
      if (mounted) {
        final List<dynamic> questions = data['questions'] ?? (data['question'] != null ? [data['question']] : []);
        final int rIdx = data['roundIndex'] ?? 0;
        final currentQ = data['question'] ?? (questions.isNotEmpty ? questions[rIdx < questions.length ? rIdx : 0] : null);
        final int totalRounds = data['totalRounds'] ?? (questions.isNotEmpty ? questions.length : _totalRounds);
        final int timePerQ = data['timePerQuestion'] ?? _timePerQuestion;

        setState(() {
          _allQuestions = questions.isNotEmpty ? questions : _allQuestions;
          _gameState = 'QUESTION';
          _currentRoundIndex = rIdx;
          _totalRounds = totalRounds;
          _timePerQuestion = timePerQ;
          _currentQuestion = currentQ;
          _selectedOptionIndex = null;
          _answerSubmitted = false;
          _secondsRemaining = timePerQ;
          _timeTakenSec = 0;
        });
        _numericAnswerCtrl.clear();
        _startTimer();
      }
    });

    socket.on('competition:player_progress', (data) {
      if (mounted && data['participants'] != null) {
        setState(() {
          _participants = _cleanParticipants(data['participants']);
        });
      }
    });

    socket.on('competition:round_ended', (data) {
      _countdownTimer?.cancel();
      if (mounted) {
        setState(() {
          _gameState = 'ROUND_RESULT';
          _currentRoundIndex = data['roundIndex'] ?? _currentRoundIndex;
          _roundLeaderboard = _cleanParticipants(data['leaderboard'] ?? []);
          _correctOptionIndex = data['correctOptionIndex'] ?? 0;
          _explanation = data['explanation'] ?? '';
        });
      }
    });

    socket.on('competition:game_over', (data) {
      _countdownTimer?.cancel();
      if (mounted) {
        setState(() {
          _gameState = 'GAME_OVER';
          _finalPodium = data['finalPodium'] ?? [];
          _roundLeaderboard = _cleanParticipants(data['leaderboard'] ?? []);
        });
      }
    });
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _secondsRemaining = 0;
          });
          if (!_answerSubmitted) {
            // On timeout: NUMERIC submits whatever's typed so far (empty
            // counts as wrong), MCQ submits an out-of-range index (also
            // always wrong, matching the pre-NUMERIC behavior here).
            if (_isNumericQuestion) {
              _submitAnswer(answerText: _numericAnswerCtrl.text.trim());
            } else {
              _submitOption(-1);
            }
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _secondsRemaining -= 1;
            _timeTakenSec += 1;
          });
        }
      }
    });
  }

  void _startWaitingPollTimer() {
    _waitingPollTimer?.cancel();
    _waitingPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_gameState == 'LOBBY' && _roomCode != null) {
        try {
          final res = await CompetitionService.getRoomByCode(_roomCode!);
          final comp = res['competition'];
          if (comp != null && mounted) {
            final List<dynamic> updatedParticipants = comp['participants'] ?? [];
            setState(() {
              _participants = _cleanParticipants(updatedParticipants);
            });

            if (comp['status'] == 'IN_PROGRESS') {
              _waitingPollTimer?.cancel();
              final List<dynamic> questions = comp['questions'] ?? [];
              if (questions.isNotEmpty) {
                setState(() {
                  _allQuestions = questions;
                  _gameState = 'QUESTION';
                  _currentRoundIndex = 0;
                  _totalRounds = questions.length;
                  _timePerQuestion = comp['timePerQuestion'] ?? 60;
                  _currentQuestion = questions[0];
                  _selectedOptionIndex = null;
                  _answerSubmitted = false;
                  _secondsRemaining = _timePerQuestion;
                  _timeTakenSec = 0;
                });
                _startTimer();
              }
            }
          }
        } catch (_) {}
      } else {
        _waitingPollTimer?.cancel();
      }
    });
  }

  Future<void> _joinRoom() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final roomData = await CompetitionService.getRoomByCode(code);

      _roomCode = code;
      final competition = roomData['competition'];

      CompetitionService.joinRoom(
        roomCode: code,
        userId: auth.user?['id'] ?? auth.user?['_id'] ?? '',
        name: auth.user?['name'] ?? 'Student',
        avatar: auth.user?['avatar'] ?? '',
      );

      _setupSocketListeners();

      final isAlreadyInProgress = competition['status'] == 'IN_PROGRESS';
      if (isAlreadyInProgress) {
        final List<dynamic> questions = competition['questions'] ?? [];
        final myUserId = (auth.user?['id'] ?? auth.user?['_id'])?.toString();
        final List<dynamic> parts = _cleanParticipants(competition['participants'] ?? []);
        final myPart = parts.firstWhere((p) => p['userId']?.toString() == myUserId, orElse: () => null);
        final List<dynamic> resps = myPart != null ? (myPart['responseHistory'] ?? []) : [];
        final startIdx = resps.length;

        setState(() {
          _allQuestions = questions;
          _participants = parts;
          _totalRounds = questions.length;
          _timePerQuestion = competition['timePerQuestion'] ?? 60;
          _isLoading = false;
        });

        if (startIdx < questions.length) {
          setState(() {
            _gameState = 'QUESTION';
            _currentRoundIndex = startIdx;
            _currentQuestion = questions[startIdx];
            _secondsRemaining = _timePerQuestion;
            _selectedOptionIndex = null;
            _answerSubmitted = false;
            _timeTakenSec = 0;
          });
          _startTimer();
        } else {
          setState(() {
            _gameState = 'GAME_OVER';
          });
        }
      } else {
        setState(() {
          _gameState = 'LOBBY';
          _participants = competition['participants'] ?? [];
          _isLoading = false;
        });
        _startWaitingPollTimer();
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _submitOption(int idx) {
    _submitAnswer(selectedOptionIndex: idx);
  }

  void _appendKey(String key) {
    if (_answerSubmitted) return;
    setState(() {
      if (key == '-') {
        if (_numericAnswerCtrl.text.startsWith('-')) {
          _numericAnswerCtrl.text = _numericAnswerCtrl.text.substring(1);
        } else {
          _numericAnswerCtrl.text = '-${_numericAnswerCtrl.text}';
        }
      } else if (key == '.') {
        if (!_numericAnswerCtrl.text.contains('.')) {
          _numericAnswerCtrl.text += _numericAnswerCtrl.text.isEmpty ? '0.' : '.';
        }
      } else {
        if (_numericAnswerCtrl.text.length < 12) {
          _numericAnswerCtrl.text += key;
        }
      }
    });
  }

  void _onBackspace() {
    if (_answerSubmitted) return;
    setState(() {
      if (_numericAnswerCtrl.text.isNotEmpty) {
        _numericAnswerCtrl.text = _numericAnswerCtrl.text.substring(0, _numericAnswerCtrl.text.length - 1);
      }
    });
  }

  void _submitNumericAnswer() {
    if (_answerSubmitted) return;
    final text = _numericAnswerCtrl.text.trim();
    if (text.isEmpty) return;
    _submitAnswer(answerText: text);
  }

  /// Shared by both answer types: records the response, sends it to the
  /// server, and advances to the next question in the arena.
  void _submitAnswer({int? selectedOptionIndex, String? answerText}) {
    if (_answerSubmitted || _gameState != 'QUESTION' || _roomCode == null) return;

    _countdownTimer?.cancel();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uId = auth.user?['id'] ?? auth.user?['_id'] ?? '';

    setState(() {
      _selectedOptionIndex = selectedOptionIndex;
      _answerSubmitted = true;
    });

    CompetitionService.submitAnswer(
      roomCode: _roomCode!,
      userId: uId,
      roundIndex: _currentRoundIndex,
      selectedOptionIndex: selectedOptionIndex,
      answerText: answerText,
      timeTakenSec: _timeTakenSec,
    );

    // Auto-advance to next question after 400ms
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;

      final nextRound = _currentRoundIndex + 1;
      if (_allQuestions != null && nextRound < _allQuestions!.length) {
        setState(() {
          _currentRoundIndex = nextRound;
          _currentQuestion = _allQuestions![nextRound];
          _selectedOptionIndex = null;
          _answerSubmitted = false;
          _secondsRemaining = _timePerQuestion;
          _timeTakenSec = 0;
        });
        _numericAnswerCtrl.clear();
        _startTimer();
      } else if (_allQuestions != null && nextRound >= _allQuestions!.length) {
        // Finished all questions in competition
        setState(() {
          _gameState = 'ROUND_RESULT';
        });
      }
    });
  }

  Widget _buildJoinState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.glassBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sports_esports_rounded,
                  color: Color(0xFF6366F1),
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Join Live Arena',
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter the 6-digit Room Code provided by your Tutor to enter the battle!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.textColor60,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeCtrl,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
                decoration: InputDecoration(
                  hintText: 'JYAM-XXXX',
                  hintStyle: TextStyle(
                    color: context.textColor54.withOpacity(0.3),
                    letterSpacing: 2,
                    fontSize: 20,
                  ),
                  filled: true,
                  fillColor: context.isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _joinRoom(),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _joinRoom,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: JyamitiLoader(strokeWidth: 2),
                        )
                      : const Icon(Icons.flash_on_rounded),
                  label: Text(
                    _isLoading ? 'JOINING...' : 'ENTER GAME ROOM',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ).animate().fade().scale(begin: const Offset(0.9, 0.9)),
    );
  }

  Widget _buildLobbyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF10B981)),
              ),
              child: Text(
                'ROOM CODE: $_roomCode',
                style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: Color(0xFF6366F1)),
            const SizedBox(height: 16),
            Text(
              'Waiting for Tutor to start the game...',
              style: TextStyle(
                color: context.textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_participants.length} Player(s) in Lobby',
              style: TextStyle(
                color: context.textColor60,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _participants.map((p) {
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: const Color(0xFF6366F1),
                    child: Text(
                      (p['name'] ?? 'S')[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  label: Text(
                    p['name'] ?? 'Student',
                    style: TextStyle(color: context.textColor, fontSize: 13),
                  ),
                  backgroundColor: context.isDark
                      ? const Color(0xFF1E293B)
                      : Colors.white,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionState() {
    if (_currentQuestion == null) return const SizedBox();

    final List<dynamic> options = _currentQuestion!['options'] ?? [];
    final double timerPct = _secondsRemaining / _timePerQuestion;
    final List<Color> optionColors = [
      const Color(0xFF6366F1),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEC4899),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Round & Timer Gauge Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'ROUND ${_currentRoundIndex + 1} / $_totalRounds',
                  style: const TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, color: Colors.amber, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${_secondsRemaining}s',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Countdown progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: timerPct,
              backgroundColor: context.isDark
                  ? const Color(0xFF334155)
                  : const Color(0xFFE2E8F0),
              color: timerPct < 0.25 ? Colors.redAccent : const Color(0xFF6366F1),
              minHeight: 8,
            ),
          ),

          const SizedBox(height: 24),

          // Question Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: LatexRichText(
              text: _currentQuestion!['text'] ?? '',
              style: TextStyle(
                color: context.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
            ),
          ),

          const SizedBox(height: 24),

          if (_isNumericQuestion)
            _buildNumericAnswerInput()
          else ...[
            Text(
              '👇 Tap an option below to submit your answer:',
              style: TextStyle(
                color: context.textColor70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            // Option Cards Grid
            GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: options.length,
            itemBuilder: (context, idx) {
              final isSelected = _selectedOptionIndex == idx;
              final Color cardColor = optionColors[idx % optionColors.length];

              return InkWell(
                onTap: _answerSubmitted ? null : () => _submitOption(idx),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? cardColor : cardColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? Colors.white : cardColor,
                      width: isSelected ? 3 : 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : cardColor.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          String.fromCharCode(65 + idx), // A, B, C, D
                          style: TextStyle(
                            color: isSelected ? cardColor : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LatexRichText(
                          text: options[idx].toString(),
                          style: TextStyle(
                            color: isSelected ? Colors.white : context.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          ],

          if (_answerSubmitted) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Text(
                    'Answer Submitted! Waiting for round results...',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ).animate().fade().scale(),
          ],
        ],
      ),
    );
  }

  /// Free-response numeric input for Math Fundamentals (NUMERIC answerType)
  /// with an on-screen 4-column custom keypad matching the requested layout.
  Widget _buildNumericAnswerInput() {
    final bool isDark = context.isDark;
    final text = _numericAnswerCtrl.text;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _submitNumericAnswer();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
            _onBackspace();
            return KeyEventResult.handled;
          } else if (event.character != null && RegExp(r'[0-9.\-]').hasMatch(event.character!)) {
            _appendKey(event.character!);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            children: [
              // Display Card showing current typed answer
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: text.isNotEmpty ? const Color(0xFF6366F1) : context.glassBorder,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: text.isNotEmpty
                          ? const Color(0xFF6366F1).withOpacity(0.15)
                          : Colors.black.withOpacity(0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        text.isEmpty ? 'Your answer' : text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: text.isEmpty ? context.textColor60 : context.textColor,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    if (text.isNotEmpty && !_answerSubmitted)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        color: context.textColor60,
                        onPressed: () => setState(() => _numericAnswerCtrl.clear()),
                        tooltip: 'Clear',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 4-Column Keypad Layout
              LayoutBuilder(
                builder: (context, constraints) {
                  const double gap = 10;
                  final double keyWidth = (constraints.maxWidth - (gap * 3)) / 4;
                  final double keyHeight = keyWidth * 0.95;

                  Widget buildKey(String label, {VoidCallback? onTap}) {
                    return SizedBox(
                      width: keyWidth,
                      height: keyHeight,
                      child: Material(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        elevation: 1.5,
                        shadowColor: Colors.black.withOpacity(0.08),
                        child: InkWell(
                          onTap: _answerSubmitted ? null : (onTap ?? () => _appendKey(label)),
                          borderRadius: BorderRadius.circular(16),
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left 3 columns (digits, minus, decimal)
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            // Row 1: 1, 2, 3
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                buildKey('1'),
                                buildKey('2'),
                                buildKey('3'),
                              ],
                            ),
                            const SizedBox(height: gap),
                            // Row 2: 4, 5, 6
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                buildKey('4'),
                                buildKey('5'),
                                buildKey('6'),
                              ],
                            ),
                            const SizedBox(height: gap),
                            // Row 3: 7, 8, 9
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                buildKey('7'),
                                buildKey('8'),
                                buildKey('9'),
                              ],
                            ),
                            const SizedBox(height: gap),
                            // Row 4: -, 0, .
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                buildKey('-'),
                                buildKey('0'),
                                buildKey('.'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: gap),

                      // Right 4th column (Backspace on Row 1 + Tall Submit Button spanning Rows 2..4)
                      SizedBox(
                        width: keyWidth,
                        child: Column(
                          children: [
                            // Row 1: Backspace button
                            SizedBox(
                              width: keyWidth,
                              height: keyHeight,
                              child: Material(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(16),
                                elevation: 1.5,
                                child: InkWell(
                                  onTap: _answerSubmitted ? null : _onBackspace,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Center(
                                    child: Icon(
                                      Icons.backspace_outlined,
                                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: gap),
                            // Rows 2..4: Tall Submit Button
                            SizedBox(
                              width: keyWidth,
                              height: (keyHeight * 3) + (gap * 2),
                              child: Material(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(16),
                                elevation: 3,
                                shadowColor: const Color(0xFF10B981).withOpacity(0.4),
                                child: InkWell(
                                  onTap: _answerSubmitted ? null : _submitNumericAnswer,
                                  borderRadius: BorderRadius.circular(16),
                                  child: const Center(
                                    child: Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoundResultState() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final String currentUserId = auth.user?['id'] ?? auth.user?['_id'] ?? '';
    final myRankObj = _roundLeaderboard.firstWhere(
      (p) => p['userId'].toString() == currentUserId,
      orElse: () => null,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.military_tech_rounded, size: 56, color: Colors.amber),
          const SizedBox(height: 12),
          Text(
            'Round ${_currentRoundIndex + 1} Results',
            style: TextStyle(
              color: context.textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (myRankObj != null) ...[
            const SizedBox(height: 6),
            Text(
              'Your Rank: #${myRankObj['rank']} (${myRankObj['totalScore']} pts)',
              style: const TextStyle(
                color: Color(0xFF6366F1),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.glassBorder),
            ),
            child: Column(
              children: [
                const Text(
                  '🏆 Round Leaderboard',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                ..._roundLeaderboard.map((p) {
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF6366F1),
                      radius: 14,
                      child: Text('#${p['rank']}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                    title: Text(p['name'] ?? 'Student', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
                    trailing: Text('${p['totalScore']} pts', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Waiting for Tutor to start Round ${_currentRoundIndex + 2}...',
                  style: const TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOverState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 72, color: Colors.amber),
            const SizedBox(height: 16),
            Text(
              'COMPETITION FINISHED!',
              style: TextStyle(
                color: context.textColor,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Return to Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'JYAMITI ARENA',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        leading: widget.isInline
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack ?? () => Navigator.maybePop(context),
                tooltip: 'Back',
              )
            : null,
        backgroundColor:
            context.isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 1,
        iconTheme: IconThemeData(color: context.textColor),
      ),
      body: _gameState == 'JOIN'
          ? _buildJoinState()
          : _gameState == 'LOBBY'
              ? _buildLobbyState()
              : _gameState == 'QUESTION'
                  ? _buildQuestionState()
                  : _gameState == 'ROUND_RESULT'
                      ? _buildRoundResultState()
                      : _buildGameOverState(),
    );
  }
}
