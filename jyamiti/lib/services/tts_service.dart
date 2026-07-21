import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TTSService extends ChangeNotifier {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  bool _isMuted = false;
  String? _currentlySpeakingText;

  bool get isSpeaking => _isSpeaking;
  bool get isMuted => _isMuted;
  String? get currentlySpeakingText => _currentlySpeakingText;

  TTSService() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.48); // Friendly, clear educational pace
      await _flutterTts.setPitch(1.1);       // Slightly upbeat, friendly tone
      await _flutterTts.setVolume(1.0);

      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
        notifyListeners();
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        _currentlySpeakingText = null;
        notifyListeners();
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        _currentlySpeakingText = null;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Error initializing FlutterTts: $e');
    }
  }

  /// Clean Markdown markup and emojis so speech synthesis sounds natural
  String cleanMarkdownForSpeech(String markdown) {
    String text = markdown;

    // Remove code blocks
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    text = text.replaceAll(RegExp(r'`([^`]+)`'), r'$1');

    // Remove headers
    text = text.replaceAll(RegExp(r'#{1,6}\s*'), '');

    // Remove bold/italics
    text = text.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
    text = text.replaceAll(RegExp(r'\*([^*]+)\*'), r'$1');
    text = text.replaceAll(RegExp(r'__([^_]+)__'), r'$1');
    text = text.replaceAll(RegExp(r'_([^_]+)_'), r'$1');

    // Remove common emojis
    text = text.replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]', unicode: true), '');

    // Clean multiple line breaks and extra spaces
    text = text.replaceAll(RegExp(r'\n+'), '. ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  /// Speak text aloud using TTS
  Future<void> speak(String text) async {
    if (_isMuted) return;

    final cleanText = cleanMarkdownForSpeech(text);
    if (cleanText.isEmpty) return;

    await stop();

    _currentlySpeakingText = text;
    _isSpeaking = true;
    notifyListeners();

    try {
      await _flutterTts.speak(cleanText);
    } catch (e) {
      debugPrint('TTS speak error: $e');
      _isSpeaking = false;
      _currentlySpeakingText = null;
      notifyListeners();
    }
  }

  /// Toggle mute status
  void toggleMute() {
    _isMuted = !_isMuted;
    if (_isMuted) {
      stop();
    }
    notifyListeners();
  }

  /// Stop current speech
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('TTS stop error: $e');
    }
    _isSpeaking = false;
    _currentlySpeakingText = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }
}
