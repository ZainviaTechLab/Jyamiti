import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService extends ChangeNotifier {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;
  String _lastWords = '';
  String _currentLocaleId = '';

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;
  String get lastWords => _lastWords;

  Future<bool> initialize() async {
    if (_isAvailable) return true;
    try {
      _isAvailable = await _speech.initialize(
        onError: (val) {
          debugPrint('Speech recognition error: ${val.errorMsg}');
          _isListening = false;
          notifyListeners();
        },
        onStatus: (val) {
          debugPrint('Speech status: $val');
          if (val == 'done' || val == 'notListening') {
            _isListening = false;
            notifyListeners();
          }
        },
      );
      if (_isAvailable) {
        final systemLocale = await _speech.systemLocale();
        _currentLocaleId = systemLocale?.localeId ?? 'en_US';
      }
    } catch (e) {
      debugPrint('SpeechToText init exception: $e');
      _isAvailable = false;
    }
    notifyListeners();
    return _isAvailable;
  }

  Future<void> startListening({
    required Function(String recognizedText) onResult,
  }) async {
    _lastWords = '';
    if (!_isAvailable) {
      final ready = await initialize();
      if (!ready) {
        debugPrint('SpeechToText not available on this device/browser');
        return;
      }
    }

    _isListening = true;
    notifyListeners();

    try {
      await _speech.listen(
        onResult: (result) {
          _lastWords = result.recognizedWords;
          onResult(_lastWords);
          notifyListeners();
        },
        localeId: _currentLocaleId.isNotEmpty ? _currentLocaleId : 'en_US',
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 10),
        cancelOnError: false,
        partialResults: true,
      );
    } catch (e) {
      debugPrint('Error starting listening: $e');
      _isListening = false;
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    if (!_isListening) return;
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('Error stopping listening: $e');
    } finally {
      _isListening = false;
      notifyListeners();
    }
  }

  void reset() {
    _lastWords = '';
    _isListening = false;
    notifyListeners();
  }
}
