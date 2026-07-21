import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ThemeProvider extends ChangeNotifier {
  static const _windowChannel = MethodChannel('com.jyamiti.app/window');
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;
  
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  ThemeProvider() {
    _syncWindowTitleBar(_isDarkMode);
  }

  void toggleTheme(bool isDark) {
    _isDarkMode = isDark;
    _syncWindowTitleBar(isDark);
    notifyListeners();
  }

  void _syncWindowTitleBar(bool isDark) {
    if (!kIsWeb && Platform.isWindows) {
      _windowChannel.invokeMethod('updateTheme', {'isDark': isDark}).catchError((e) {
        debugPrint('Failed to sync window title bar: $e');
      });
    }
  }
}

extension ThemeContextExtension on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get textColor => isDark ? Colors.white : const Color(0xFF0F172A);
  Color get textColor70 => isDark ? Colors.white70 : const Color(0xFF475569);
  Color get textColor60 => isDark ? Colors.white60 : const Color(0xFF64748B);
  Color get textColor54 => isDark ? Colors.white54 : const Color(0xFF94A3B8);
  Color get textMuted => isDark ? Colors.white70 : const Color(0xFF475569);
  Color get textFaint => isDark ? Colors.white54 : const Color(0xFF94A3B8);
  static const Color jyamitiCosmosColor = Color(0xFF0F2B52);
  Color get jyamitiCosmos => const Color(0xFF0F2B52);
  Color get jyamitiBg => jyamitiCosmos;
  Color get glassBg => isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
  Color get glassBorder => isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);
}

