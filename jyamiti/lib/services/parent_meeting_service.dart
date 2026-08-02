import 'dart:convert';
import 'api_service.dart';

class ParentMeetingService {
  // Helper for safe JSON parsing
  static Map<String, dynamic> _parseResponse(String body, int statusCode) {
    try {
      if (body.trim().startsWith('{') || body.trim().startsWith('[')) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'data': decoded};
      }
    } catch (_) {}
    throw Exception('Server Error ($statusCode): ${body.length > 80 ? body.substring(0, 80) : body}');
  }

  // 1. Schedule a new parent meeting (Tutor/Admin)
  static Future<Map<String, dynamic>> createMeeting({
    required String title,
    String? description,
    required String batchId,
    required String scheduledAt,
    int durationMinutes = 45,
  }) async {
    final response = await ApiService.post('/parent-meetings/create', {
      'title': title,
      'description': description ?? '',
      'batchId': batchId,
      'scheduledAt': scheduledAt,
      'durationMinutes': durationMinutes,
    });

    final data = _parseResponse(response.body, response.statusCode);
    if (response.statusCode == 201 || response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to schedule parent meeting.');
    }
  }

  // 2. Fetch meetings for a batch
  static Future<List<dynamic>> getBatchMeetings(String batchId) async {
    final response = await ApiService.get('/parent-meetings/batch/$batchId');
    if (response.statusCode == 200) {
      final data = _parseResponse(response.body, response.statusCode);
      return data['meetings'] ?? [];
    } else {
      throw Exception('Failed to fetch batch meetings.');
    }
  }

  // 3. Fetch meetings for current logged in user (Tutor/Admin or Student/Parent)
  static Future<List<dynamic>> getMyMeetings() async {
    final response = await ApiService.get('/parent-meetings/my-meetings');
    if (response.statusCode == 200) {
      final data = _parseResponse(response.body, response.statusCode);
      return data['meetings'] ?? [];
    } else {
      throw Exception('Failed to fetch meetings.');
    }
  }

  // 4. Update meeting status (scheduled, live, ended)
  static Future<Map<String, dynamic>> updateMeetingStatus(
      String meetingId, String status) async {
    final response = await ApiService.put('/parent-meetings/$meetingId/status', {
      'status': status,
    });

    final data = _parseResponse(response.body, response.statusCode);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Failed to update meeting status.');
    }
  }

  // 5. Delete meeting
  static Future<void> deleteMeeting(String meetingId) async {
    final response = await ApiService.delete('/parent-meetings/$meetingId');
    if (response.statusCode != 200) {
      final data = _parseResponse(response.body, response.statusCode);
      throw Exception(data['message'] ?? 'Failed to delete meeting.');
    }
  }

  // 6. Fetch Agora RTC Token for channel
  static Future<String?> getRtcToken({
    required String channelName,
    required bool isHost,
  }) async {
    try {
      final response = await ApiService.get(
        '/parent-meetings/rtc-token?channelName=$channelName&isHost=$isHost',
      );
      if (response.statusCode == 200) {
        final data = _parseResponse(response.body, response.statusCode);
        return data['token'] as String?;
      }
    } catch (e) {
      print('Error fetching RTC token: $e');
    }
    return null;
  }
}
