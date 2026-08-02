import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/jyammy_service.dart';
import '../../services/speech_service.dart';
import '../../services/tts_service.dart';

class AskJyammyDialog extends StatefulWidget {
  const AskJyammyDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AskJyammyDialog(),
    );
  }

  @override
  State<AskJyammyDialog> createState() => _AskJyammyDialogState();
}

class _AskJyammyDialogState extends State<AskJyammyDialog> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late SpeechService _speechService;
  late TTSService _ttsService;

  List<Map<String, String>> _messages = [];
  bool _isLoadingHistory = true;
  bool _isThinking = false;
  bool _isHoldingToSpeak = false;
  String _liveSpokenText = '';

  int _dailyCount = 0;
  DateTime? _banExpiry;

  @override
  void initState() {
    super.initState();
    _speechService = SpeechService();
    _speechService.initialize();
    _ttsService = TTSService();
    _ttsService.addListener(() {
      if (mounted) setState(() {});
    });
    _loadChatData();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _speechService.stopListening();
    _ttsService.stop();
    _ttsService.dispose();
    super.dispose();
  }

  Future<void> _loadChatData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userId = auth.userId ?? 'guest_student';
    
    final history = await JyammyService.loadHistory(userId);
    final dailyCount = await JyammyService.getDailyCount(userId);
    final banExpiry = await JyammyService.getBanExpiry(userId);

    if (mounted) {
      setState(() {
        _messages = history;
        _dailyCount = dailyCount;
        _banExpiry = banExpiry;
        _isLoadingHistory = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendQuery(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty || _isThinking) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userId = auth.userId ?? 'guest_student';

    // 1. Check if user is currently banned
    if (_banExpiry != null && DateTime.now().isBefore(_banExpiry!)) {
      _showSnackBar(
        '⛔ Chat Suspended: You cannot send messages until ${_banExpiry!.day}/${_banExpiry!.month}/${_banExpiry!.year} for asking non-math doubts.',
        isError: true,
      );
      return;
    }

    // 2. Check if daily quota of 10 doubts is reached
    if (_dailyCount >= JyammyService.maxDailyDoubts) {
      _showSnackBar(
        '⚠️ Daily limit reached! You can ask a maximum of 10 doubts per day. Please return tomorrow! 🤖',
        isError: true,
      );
      return;
    }

    final userMap = auth.user ?? {};
    final profileMap = auth.profile ?? {};
    final Map<String, dynamic> studentProfile = {
      'name': auth.userName ?? userMap['name'] ?? 'Student',
      'email': auth.userEmail ?? userMap['email'] ?? '',
      'grade': userMap['grade'] ?? profileMap['grade'] ?? '8',
      'batches': profileMap['enrolledBatches'] ?? userMap['batches'] ?? [],
    };

    setState(() {
      _messages.add({'sender': 'user', 'text': cleanText, 'time': DateTime.now().toIso8601String()});
      _textCtrl.clear();
      _liveSpokenText = '';
      _isThinking = true;
    });
    _scrollToBottom();

    try {
      final JyammyResult result = await JyammyService.askJyammy(
        userId: userId,
        query: cleanText,
        studentData: studentProfile,
        history: _messages,
      );

      final updatedDailyCount = await JyammyService.getDailyCount(userId);

      if (mounted) {
        setState(() {
          _messages.add({'sender': 'jyammy', 'text': result.reply, 'time': DateTime.now().toIso8601String()});
          _dailyCount = updatedDailyCount;
          if (!result.isMathRelated) {
            _banExpiry = result.banExpiry;
          }
        });
        await JyammyService.saveHistory(userId, _messages);

        // Auto speak Jyammy's response!
        _ttsService.speak(result.reply);

        if (!result.isMathRelated) {
          _showBanWarningDialog(result.banExpiry);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({
            'sender': 'jyammy',
            'text': '🤖 Beep boop! I had trouble connecting to my AI brain. Please check your connection and try again!',
            'time': DateTime.now().toIso8601String()
          });
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isThinking = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _showBanWarningDialog(DateTime? expiry) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text(
              '7-Day Chat Suspension',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Warning: Jyammy is strictly for Mathematics and study doubts!\n\nYour question was flagged as non-mathematical. Access to Jyammy AI chat has been suspended for 7 days until ${expiry?.day}/${expiry?.month}/${expiry?.year}.',
          style: TextStyle(color: context.textColor70, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('I Understand', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _onPressHoldStart() {
    if (_banExpiry != null && DateTime.now().isBefore(_banExpiry!)) {
      _showSnackBar('⛔ Chat Suspended: You cannot speak/send doubts until ${_banExpiry!.day}/${_banExpiry!.month}/${_banExpiry!.year}.', isError: true);
      return;
    }
    if (_dailyCount >= JyammyService.maxDailyDoubts) {
      _showSnackBar('⚠️ Daily limit reached (10/10 doubts)! Return tomorrow.', isError: true);
      return;
    }

    setState(() {
      _isHoldingToSpeak = true;
      _liveSpokenText = '';
    });

    _speechService.startListening(
      onResult: (text) {
        if (mounted) {
          setState(() {
            _liveSpokenText = text;
          });
        }
      },
    );
  }

  void _onPressHoldEnd() {
    if (!_isHoldingToSpeak) return;
    _speechService.stopListening();
    setState(() {
      _isHoldingToSpeak = false;
    });

    final spoken = _liveSpokenText.isNotEmpty ? _liveSpokenText : _speechService.lastWords;
    if (spoken.trim().isNotEmpty) {
      _handleSendQuery(spoken);
    }
  }

  Future<void> _handleClearMemory() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userId = auth.userId ?? 'guest_student';
    await JyammyService.clearHistory(userId);
    if (mounted) {
      setState(() {
        _messages.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final auth = Provider.of<AuthProvider>(context);
    final studentName = auth.userName ?? 'Student';
    final studentGrade = auth.user?['grade'] ?? auth.profile?['grade'] ?? '8';
    final bool isBanned = _banExpiry != null && DateTime.now().isBefore(_banExpiry!);
    final bool isLimitReached = _dailyCount >= JyammyService.maxDailyDoubts;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.2),
              blurRadius: 30,
              spreadRadius: 5,
            )
          ],
        ),
        child: Column(
          children: [
            // Drag Handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.textColor60.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: isBanned
                                ? [Colors.red, Colors.redAccent]
                                : [const Color(0xFF6366F1), const Color(0xFFA855F7)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isBanned ? Colors.red : const Color(0xFF6366F1)).withOpacity(0.5),
                              blurRadius: 12,
                              spreadRadius: 2,
                            )
                          ],
                        ),
                      ),
                      isBanned
                          ? const Text('🚫', style: TextStyle(fontSize: 24))
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset('assets/image/Jyammy.png', width: 34, height: 34, fit: BoxFit.cover),
                            ),
                    ],
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                   .scaleXY(begin: 0.95, end: 1.05, duration: 1500.ms),
                  const SizedBox(width: 14),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Ask Jyammy',
                              style: TextStyle(
                                color: context.textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Daily Quota Pill Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isLimitReached
                                    ? Colors.redAccent.withOpacity(0.2)
                                    : const Color(0xFF6366F1).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isLimitReached
                                      ? Colors.redAccent.withOpacity(0.5)
                                      : const Color(0xFF6366F1).withOpacity(0.4),
                                ),
                              ),
                              child: Text(
                                isLimitReached ? 'Quota 10/10 (Limit)' : 'Doubts: $_dailyCount/10',
                                style: TextStyle(
                                  color: isLimitReached ? Colors.redAccent : const Color(0xFF818CF8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hi $studentName • Grade $studentGrade Math Assistant',
                          style: TextStyle(
                            color: context.textColor70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    icon: Icon(
                      _ttsService.isMuted
                          ? Icons.volume_off_rounded
                          : (_ttsService.isSpeaking ? Icons.volume_up_rounded : Icons.volume_down_rounded),
                      color: _ttsService.isSpeaking ? const Color(0xFF6366F1) : context.textColor70,
                    ),
                    tooltip: _ttsService.isMuted ? 'Unmute Voice' : 'Mute Voice',
                    onPressed: () {
                      _ttsService.toggleMute();
                    },
                  ),

                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: context.textColor70),
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    onSelected: (val) {
                      if (val == 'clear') _handleClearMemory();
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'clear',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                            const SizedBox(width: 8),
                            Text('Clear History Memory', style: TextStyle(color: context.textColor, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: context.textColor70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Active Suspension Warning Banner (if banned)
            if (isBanned)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.redAccent.withOpacity(0.15),
                child: Row(
                  children: [
                    const Icon(Icons.lock_clock_rounded, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'SUSPENDED (7-Day Policy Violation): Chat locked until ${_banExpiry!.day}/${_banExpiry!.month}/${_banExpiry!.year}. Non-math queries are prohibited.',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            // Chat Message Stream
            Expanded(
              child: _isLoadingHistory
                  ? const Center(child: JyamitiLoader(color: Color(0xFF6366F1)))
                  : _messages.isEmpty
                      ? _buildEmptyState(studentName)
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length + (_isThinking ? 1 : 0),
                          itemBuilder: (ctx, idx) {
                            if (idx == _messages.length && _isThinking) {
                              return _buildThinkingBubble();
                            }
                            final msg = _messages[idx];
                            final isUser = msg['sender'] == 'user';
                            return _buildMessageBubble(msg['text'] ?? '', isUser);
                          },
                        ),
            ),

            // Live Speech Listening Overlay (when holding button)
            if (_isHoldingToSpeak)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.5),
                      blurRadius: 15,
                    )
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: Colors.white, size: 24)
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Listening to your doubt...',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            _liveSpokenText.isEmpty ? 'Keep holding and speak clearly...' : '"$_liveSpokenText"',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Bottom Input Controls
            if (isBanned)
              Container(
                padding: const EdgeInsets.all(16),
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                child: const Center(
                  child: Text(
                    '🔒 Chat input is locked during your 7-day suspension.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else if (isLimitReached)
              Container(
                padding: const EdgeInsets.all(16),
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                child: const Center(
                  child: Text(
                    '⚠️ Daily limit of 10 doubts reached. Inputs locked until tomorrow.',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: context.glassBorder)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        style: TextStyle(color: context.textColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Type your math doubt here...',
                          hintStyle: TextStyle(color: context.textColor60.withOpacity(0.6), fontSize: 13),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: _handleSendQuery,
                      ),
                    ),
                    const SizedBox(width: 8),

                    GestureDetector(
                      onLongPressStart: (_) => _onPressHoldStart(),
                      onLongPressEnd: (_) => _onPressHoldEnd(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _isHoldingToSpeak
                                ? [Colors.redAccent, Colors.pinkAccent]
                                : [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: (_isHoldingToSpeak ? Colors.redAccent : const Color(0xFF6366F1)).withOpacity(0.4),
                              blurRadius: 8,
                            )
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isHoldingToSpeak ? Icons.mic_rounded : Icons.mic_none_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isHoldingToSpeak ? 'Release' : 'Hold Speak',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF6366F1)),
                      onPressed: () => _handleSendQuery(_textCtrl.text),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String studentName) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/image/Jyammy.png', width: 72, height: 72, fit: BoxFit.contain)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 2.seconds),
            const SizedBox(height: 12),
            Text(
              'Hi $studentName! I\'m Jyammy ⚡',
              style: TextStyle(
                color: context.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ask up to 10 math doubts per day! Non-math questions will result in a 7-day chat suspension. Hold to speak or type below.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.textColor70,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildQuickChip('📐 Explain Pythagoras Theorem'),
                _buildQuickChip('🔢 How to solve 2x + 5 = 15?'),
                _buildQuickChip('💡 Geometry area formulas'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip(String label) {
    final isDark = context.isDark;
    return ActionChip(
      backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      side: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.3)),
      label: Text(label, style: TextStyle(color: context.textColor, fontSize: 12)),
      onPressed: () => _handleSendQuery(label.substring(2).trim()),
    );
  }

  Widget _buildMessageBubble(String text, bool isUser) {
    final isDark = context.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF6366F1),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset('assets/image/Jyammy.png', width: 22, height: 22, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF6366F1)
                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(color: context.glassBorder),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isUser ? Colors.white : context.textColor,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (!isUser) ...[
            const SizedBox(width: 2),
            IconButton(
              icon: Icon(
                _ttsService.isSpeaking && _ttsService.currentlySpeakingText == text
                    ? Icons.stop_circle_rounded
                    : Icons.volume_up_rounded,
                size: 18,
                color: _ttsService.isSpeaking && _ttsService.currentlySpeakingText == text
                    ? Colors.redAccent
                    : context.textColor60.withOpacity(0.7),
              ),
              tooltip: _ttsService.isSpeaking && _ttsService.currentlySpeakingText == text
                  ? 'Stop Speaking'
                  : 'Listen to Answer',
              onPressed: () {
                if (_ttsService.isSpeaking && _ttsService.currentlySpeakingText == text) {
                  _ttsService.stop();
                } else {
                  _ttsService.speak(text);
                }
              },
            ),
          ],
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFFA855F7),
              child: Icon(Icons.person, size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThinkingBubble() {
    final isDark = context.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF6366F1),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset('assets/image/Jyammy.png', width: 22, height: 22, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: JyamitiLoader(
                    strokeWidth: 2,
                    color: Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Jyammy is thinking...',
                  style: TextStyle(color: context.textColor70, fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
