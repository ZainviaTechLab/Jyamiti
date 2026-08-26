import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'api_service.dart';

/// Lightweight, dedicated Socket.io connection whose only job is to join
/// the caller's personal room (`setup` -- the exact same mechanism
/// backend/socket.js already uses for chat's own out-of-room
/// `new_message_notification` push) and listen for
/// `class_meeting:started`/`class_meeting:ended`.
///
/// Deliberately a SEPARATE connection from `ChatBloc`'s own socket rather
/// than reusing it: that one only connects when the Chat screen is
/// actually opened (`ConnectSocket` is dispatched from
/// `chat_list_screen.dart`, nowhere else) -- a student sitting on their
/// dashboard, not Chat, still needs to hear about a class starting in
/// real time, so this connects independently as soon as a dashboard
/// mounts (see `student_dashboard.dart`/`tutor_dashboard.dart`).
class ClassMeetingSocketService {
  ClassMeetingSocketService._();
  static final ClassMeetingSocketService instance =
      ClassMeetingSocketService._();

  IO.Socket? _socket;
  String? _connectedUserId;

  void Function(Map<String, dynamic> meeting)? onClassStarted;
  void Function(String meetingId)? onClassEnded;

  void connect(String userId) {
    if (_socket != null && _socket!.connected && _connectedUserId == userId) {
      return;
    }
    _socket?.dispose();

    _connectedUserId = userId;
    final String serverUrl = ApiService.serverBaseUrl;
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
    });

    _socket!.onConnect((_) {
      _socket!.emit('setup', userId);
    });
    _socket!.on('class_meeting:started', (data) {
      if (data is Map && data['meeting'] is Map) {
        onClassStarted?.call(Map<String, dynamic>.from(data['meeting'] as Map));
      }
    });
    _socket!.on('class_meeting:ended', (data) {
      if (data is Map && data['meetingId'] != null) {
        onClassEnded?.call(data['meetingId'].toString());
      }
    });
    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connectedUserId = null;
    onClassStarted = null;
    onClassEnded = null;
  }
}
