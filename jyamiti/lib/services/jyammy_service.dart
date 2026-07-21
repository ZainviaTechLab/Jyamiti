import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class JyammyResult {
  final String reply;
  final bool isMathRelated;
  final bool isDailyLimitReached;
  final DateTime? banExpiry;

  JyammyResult({
    required this.reply,
    this.isMathRelated = true,
    this.isDailyLimitReached = false,
    this.banExpiry,
  });
}

class JyammyService {
  static const String _apiKey = 'sk-6c733e978e1c4bdeaaf4a5f5084d3184';
  static const String _endpoint = 'https://api.deepseek.com/chat/completions';
  static const int maxDailyDoubts = 10;

  static String _historyKey(String userId) => 'jyammy_history_$userId';
  static String _banKey(String userId) => 'jyammy_ban_$userId';
  
  static String _todayKey(String userId) {
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    return 'jyammy_daily_${userId}_$dateStr';
  }

  /// Get current student's daily doubt count for today
  static Future<int> getDailyCount(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_todayKey(userId)) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Increment today's doubt count
  static Future<int> incrementDailyCount(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_todayKey(userId)) ?? 0;
      final updated = current + 1;
      await prefs.setInt(_todayKey(userId), updated);
      return updated;
    } catch (_) {
      return 0;
    }
  }

  /// Check if user is currently banned for 7 days
  static Future<DateTime?> getBanExpiry(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isoStr = prefs.getString(_banKey(userId));
      if (isoStr != null && isoStr.isNotEmpty) {
        final expiry = DateTime.parse(isoStr);
        if (DateTime.now().isBefore(expiry)) {
          return expiry;
        } else {
          // Ban has expired, clean up
          await prefs.remove(_banKey(userId));
        }
      }
    } catch (e) {
      debugPrint('Error checking ban expiry: $e');
    }
    return null;
  }

  /// Apply 7-day suspension for non-math doubts
  static Future<DateTime> applySevenDayBan(String userId) async {
    final expiry = DateTime.now().add(const Duration(days: 7));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_banKey(userId), expiry.toIso8601String());
    } catch (e) {
      debugPrint('Error applying 7 day ban: $e');
    }
    return expiry;
  }

  /// Load persistent chat history for a student
  static Future<List<Map<String, String>>> loadHistory(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey(userId));
      if (raw != null && raw.isNotEmpty) {
        final List decoded = jsonDecode(raw);
        return decoded.map((e) => Map<String, String>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('Error loading Jyammy chat history: $e');
    }
    return [];
  }

  /// Save persistent chat history for a student
  static Future<void> saveHistory(String userId, List<Map<String, String>> history) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listToSave = history.length > 30 ? history.sublist(history.length - 30) : history;
      await prefs.setString(_historyKey(userId), jsonEncode(listToSave));
    } catch (e) {
      debugPrint('Error saving Jyammy chat history: $e');
    }
  }

  /// Clear persistent history for a student
  static Future<void> clearHistory(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey(userId));
    } catch (e) {
      debugPrint('Error clearing Jyammy chat history: $e');
    }
  }

  /// Send a student doubt/question to Jyammy AI with full student context memory & policy checks
  static Future<JyammyResult> askJyammy({
    required String userId,
    required String query,
    required Map<String, dynamic> studentData,
    required List<Map<String, String>> history,
  }) async {
    // 1. Check if user is currently banned
    final banExpiry = await getBanExpiry(userId);
    if (banExpiry != null) {
      return JyammyResult(
        reply: '⛔ Chat Access Suspended: Jyammy is strictly for Mathematics doubts. Your access has been locked until ${banExpiry.day}/${banExpiry.month}/${banExpiry.year}.',
        isMathRelated: false,
        banExpiry: banExpiry,
      );
    }

    // 2. Check if 10 doubts/day limit reached
    final currentDailyCount = await getDailyCount(userId);
    if (currentDailyCount >= maxDailyDoubts) {
      return JyammyResult(
        reply: '⚠️ Daily limit of 10 doubts reached for today! Please come back tomorrow to ask more doubts. 🤖⚡',
        isDailyLimitReached: true,
      );
    }

    final String name = studentData['name'] ?? 'Student';
    final dynamic gradeVal = studentData['grade'] ?? studentData['gradeLevel'] ?? '8';
    final String email = studentData['email'] ?? '';
    
    String batchDetails = 'Standard Mathematics Batch';
    if (studentData['batches'] != null && studentData['batches'] is List) {
      final List bList = studentData['batches'];
      if (bList.isNotEmpty) {
        batchDetails = bList.map((b) => b['name'] ?? b['title'] ?? b.toString()).join(', ');
      }
    } else if (studentData['enrolledBatches'] != null && studentData['enrolledBatches'] is List) {
      batchDetails = (studentData['enrolledBatches'] as List).join(', ');
    }

    final systemPrompt = '''
You are "Jyammy", a super friendly, encouraging, and intelligent AI math robot and tutor for Jyamiti Math Academy.
You are talking to $name, a student in Grade $gradeVal.

STUDENT PROFILE & MEMORY CONTEXT:
- Student Name: $name
- Email: $email
- Grade Level: Grade $gradeVal
- Enrolled Courses / Batches: $batchDetails

STRICT ACADEMY CONTENT POLICY & CLASSIFICATION:
You MUST return your response in a valid JSON object format with two fields:
{
  "is_math_related": boolean (true if question is about mathematics, geometry, algebra, STEM, school study doubts, or greeting Jyammy; false if question is off-topic non-math like movies, entertainment, sports, general chatter, politics, or inappropriate content),
  "reply": string (Your friendly explanation or your warning message)
}

RULES:
1. If "is_math_related" is false:
   Provide a polite warning in "reply" stating: "Warning: Jyammy is strictly for Mathematics and study doubts! Non-math questions violate Jyamiti policy."
2. If "is_math_related" is true:
   - Always address $name naturally.
   - Explain at Grade $gradeVal level with simple step-by-step math breakdowns.
   - Be friendly as Jyammy the AI Robot 🤖!
   - Keep responses concise (2 to 4 paragraphs max) with clear Markdown for equations.
''';

    final List<Map<String, String>> apiMessages = [
      {'role': 'system', 'content': systemPrompt},
    ];

    final recentHistory = history.length > 10 ? history.sublist(history.length - 10) : history;
    for (var msg in recentHistory) {
      apiMessages.add({
        'role': msg['sender'] == 'user' ? 'user' : 'assistant',
        'content': msg['text'] ?? '',
      });
    }

    apiMessages.add({
      'role': 'user',
      'content': query,
    });

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'messages': apiMessages,
        'response_format': {
          'type': 'json_object'
        },
        'temperature': 0.7,
        'max_tokens': 1000,
      }),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final content = body['choices'][0]['message']['content'] as String;
      
      bool isMathRelated = true;
      String replyText = content.trim();

      try {
        final parsedJson = jsonDecode(content);
        if (parsedJson['is_math_related'] != null) {
          isMathRelated = parsedJson['is_math_related'] == true;
        }
        if (parsedJson['reply'] != null) {
          replyText = parsedJson['reply'].toString().trim();
        }
      } catch (_) {
        // Fallback to text matching if JSON parsing fails
      }

      if (!isMathRelated) {
        // Apply 7 day ban for non-math question
        final expiry = await applySevenDayBan(userId);
        return JyammyResult(
          reply: '$replyText\n\n⛔ WARNING: Non-math questions violate policy. Your chat access has been suspended for 7 days (until ${expiry.day}/${expiry.month}/${expiry.year}).',
          isMathRelated: false,
          banExpiry: expiry,
        );
      } else {
        // Valid math doubt: increment daily count
        await incrementDailyCount(userId);
        return JyammyResult(
          reply: replyText,
          isMathRelated: true,
        );
      }
    } else {
      throw Exception('Jyammy AI server response error: ${response.statusCode}');
    }
  }
}
