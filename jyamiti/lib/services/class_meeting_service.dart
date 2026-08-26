import 'dart:convert';
import 'api_service.dart';

/// "Start Class" -- a tutor-initiated, on-demand live class video call for
/// a batch, always tied to that batch's Schedule entry for today. Backed
/// by a separate `ClassMeeting` collection from `ParentMeeting` (different
/// lifecycle: never pre-scheduled ahead of time), but deliberately using
/// the SAME field names (`title`/`channelName`/`agoraAppId`/`hostName`/
/// `batchName`/`status`) so the meeting maps this returns can be handed
/// straight to the same `ParentMeetingRoomScreen` used for parent
/// meetings -- see that screen and `backend/models/ClassMeeting.js`'s doc
/// comments.
class ClassMeetingService {
  static Map<String, dynamic> _parseResponse(String body, int statusCode) {
    try {
      if (body.trim().startsWith('{') || body.trim().startsWith('[')) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'data': decoded};
      }
    } catch (_) {}
    throw Exception(
      'Server Error ($statusCode): ${body.length > 80 ? body.substring(0, 80) : body}',
    );
  }

  /// Starts (or, if one is already live for today's schedule, rejoins)
  /// a batch's class. Throws if the batch has no schedule today, or the
  /// caller doesn't tutor that batch -- see `POST /class-meetings/start`.
  static Future<Map<String, dynamic>> startClass(String batchId) async {
    final response = await ApiService.post('/class-meetings/start', {
      'batchId': batchId,
    });
    final data = _parseResponse(response.body, response.statusCode);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return data['meeting'] as Map<String, dynamic>;
    }
    throw Exception(data['message'] ?? 'Failed to start class.');
  }

  static Future<void> endClass(String meetingId) async {
    final response = await ApiService.put('/class-meetings/$meetingId/end', {});
    if (response.statusCode != 200) {
      final data = _parseResponse(response.body, response.statusCode);
      throw Exception(data['message'] ?? 'Failed to end class.');
    }
  }

  /// One call feeding every batch card's Start Class button state at
  /// once (tutor only) -- see `GET /class-meetings/my-today`. Each entry:
  /// `{batchId, batchName, hasScheduleToday, liveMeeting}`.
  static Future<List<Map<String, dynamic>>> getMyTodayStatus() async {
    final response = await ApiService.get('/class-meetings/my-today');
    if (response.statusCode == 200) {
      final data = _parseResponse(response.body, response.statusCode);
      return List<Map<String, dynamic>>.from(data['batches'] ?? []);
    }
    throw Exception('Failed to check today\'s schedule.');
  }

  /// Any class currently live among the caller's own batches (tutor or
  /// student) -- see `GET /class-meetings/my-live`.
  static Future<List<Map<String, dynamic>>> getMyLiveMeetings() async {
    final response = await ApiService.get('/class-meetings/my-live');
    if (response.statusCode == 200) {
      final data = _parseResponse(response.body, response.statusCode);
      return List<Map<String, dynamic>>.from(data['meetings'] ?? []);
    }
    throw Exception('Failed to check for live classes.');
  }
}
