import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'api_service.dart';

/// Dedicated Socket.io connection for the "live class presentation" feature
/// (see backend/socket.js's `class_meeting:*` handlers) -- the tutor
/// sharing slides (and, later, other resource types) with everyone
/// currently in a live class room. Deliberately a SEPARATE connection from
/// [ClassMeetingSocketService] (the dashboard-level "did a class
/// start/end" notifier, connected while sitting on the dashboard) and from
/// [ChatBloc]'s socket: this one is scoped to a single meeting room and
/// only needs to exist while [ClassMeetingRoomScreen] is actually open --
/// connect() when the room screen mounts, disconnect() when it's torn
/// down, one instance per room visit rather than a long-lived singleton.
class ClassPresentationSocketService {
  IO.Socket? _socket;
  String? _meetingId;

  void Function(Map<String, dynamic>? presentedContent)? onPresentationUpdate;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String meetingId) {
    if (_socket != null && _socket!.connected && _meetingId == meetingId) {
      return;
    }
    disconnect();

    _meetingId = meetingId;
    final String serverUrl = ApiService.serverBaseUrl;
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
    });

    _socket!.onConnect((_) {
      _socket!.emit('class_meeting:join_room', {'meetingId': meetingId});
    });
    _socket!.on('class_meeting:presentation_update', (data) {
      if (data is Map && data['meetingId'] == meetingId) {
        final content = data['presentedContent'];
        onPresentationUpdate?.call(
          content is Map ? Map<String, dynamic>.from(content) : null,
        );
      }
    });
    _socket!.connect();
  }

  /// Fired by the host's slide-navigation controls -- persists the new
  /// state on the backend and broadcasts it to everyone in the room
  /// (including this same socket, so the host's own view stays in sync
  /// through the same path as everyone else's, rather than trusting local
  /// state to match what actually got saved).
  void presentSlide({
    required String meetingId,
    required String hostId,
    required String deckId,
    required String deckTitle,
    required int slideIndex,
    required int totalSlides,
  }) {
    _socket?.emit('class_meeting:present_slide', {
      'meetingId': meetingId,
      'hostId': hostId,
      'deckId': deckId,
      'deckTitle': deckTitle,
      'slideIndex': slideIndex,
      'totalSlides': totalSlides,
    });
  }

  void stopPresenting({required String meetingId, required String hostId}) {
    _socket?.emit('class_meeting:stop_presenting', {
      'meetingId': meetingId,
      'hostId': hostId,
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _meetingId = null;
    onPresentationUpdate = null;
  }
}
