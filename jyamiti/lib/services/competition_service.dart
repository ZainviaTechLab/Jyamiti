import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_service.dart';

class CompetitionService {
  static io.Socket? _socket;

  // Initialize Socket.io connection for Arena Competitions
  static void initSocket(String baseUrl) {
    if (_socket != null && _socket!.connected) return;

    // Strip only a trailing "/api" suffix -- NOT baseUrl.replaceAll('/api',
    // ''), which also mangles the "api" in "https://api.jyamitimath.com"
    // itself (see ApiService.serverBaseUrl's doc comment for the verified
    // broken output). Takes `baseUrl` as a param rather than reading
    // `ApiService.serverBaseUrl` directly to keep this method's existing
    // signature/testability, but callers always pass `ApiService.baseUrl`.
    final socketUrl =
        baseUrl.endsWith('/api') ? baseUrl.substring(0, baseUrl.length - 4) : baseUrl;
    _socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('⚡ Arena Socket Connected: ${_socket!.id}');
    });

    _socket!.onDisconnect((_) {
      debugPrint('🔌 Arena Socket Disconnected');
    });
  }

  static io.Socket? get socket => _socket;

  // Fetch curriculum topics for a batch's course
  static Future<Map<String, dynamic>> getBatchTopics(String batchId) async {
    final response = await ApiService.get('/competitions/batch/$batchId/topics');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load batch curriculum topics.');
    }
  }

  // 1. Create a new competition room (Tutor/Admin)
  static Future<Map<String, dynamic>> createCompetition({
    required String title,
    required String batchId,
    required int grade,
    required int numberOfRounds,
    required int roundDurationMinutes,
    List<String>? selectedTopics,
    List<Map<String, dynamic>>? questions,
  }) async {
    final response = await ApiService.post('/competitions/create', {
      'title': title,
      'batchId': batchId,
      'grade': grade,
      'numberOfRounds': numberOfRounds,
      'roundDurationMinutes': roundDurationMinutes,
      'selectedTopics': selectedTopics ?? [],
      'questions': questions ?? [],
    });

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Failed to create competition');
    }
  }

  // 2. Fetch competition room details by Room Code
  static Future<Map<String, dynamic>> getRoomByCode(String roomCode) async {
    final response = await ApiService.get('/competitions/room/$roomCode');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Room not found.');
    }
  }

  // 3. Fetch past competitions for a batch
  static Future<List<dynamic>> getBatchCompetitions(String batchId) async {
    final response = await ApiService.get('/competitions/batch/$batchId');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['competitions'] ?? [];
    } else {
      throw Exception('Failed to fetch batch competitions.');
    }
  }

  // 4. Fetch detailed analytics for a competition
  static Future<Map<String, dynamic>> getCompetitionAnalytics(String competitionId) async {
    final response = await ApiService.get('/competitions/$competitionId/analytics');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch competition analytics.');
    }
  }

  // Real-Time Socket Event Emitters
  static Future<void> joinRoom({
    required String roomCode,
    required String userId,
    required String name,
    String avatar = '',
  }) async {
    _socket?.emit('competition:join_room', {
      'roomCode': roomCode,
      'userId': userId,
      'name': name,
      'avatar': avatar,
    });

    try {
      await ApiService.post('/competitions/join', {
        'roomCode': roomCode,
        'name': name,
        'avatar': avatar,
      });
    } catch (e) {
      debugPrint('HTTP join backup error: $e');
    }
  }

  static Future<void> startGame(String roomCode) async {
    _socket?.emit('competition:start_game', {'roomCode': roomCode});
    try {
      await ApiService.post('/competitions/start', {'roomCode': roomCode});
    } catch (e) {
      debugPrint('HTTP startGame backup error: $e');
    }
  }

  static void submitAnswer({
    required String roomCode,
    required String userId,
    int? roundIndex,
    required int selectedOptionIndex,
    required int timeTakenSec,
  }) {
    _socket?.emit('competition:submit_answer', {
      'roomCode': roomCode,
      'userId': userId,
      'roundIndex': roundIndex,
      'selectedOptionIndex': selectedOptionIndex,
      'timeTakenSec': timeTakenSec,
    });
  }

  static void endRound(String roomCode) {
    _socket?.emit('competition:end_round', {'roomCode': roomCode});
  }

  static void nextRound(String roomCode) {
    _socket?.emit('competition:next_round', {'roomCode': roomCode});
  }

  static void endGame(String roomCode) {
    _socket?.emit('competition:end_game', {'roomCode': roomCode});
  }

  static void leaveRoom(String roomCode) {
    _socket?.off('competition:player_joined');
    _socket?.off('competition:round_started');
    _socket?.off('competition:answer_submitted');
    _socket?.off('competition:round_ended');
    _socket?.off('competition:game_over');
  }
}
