import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class OfflineSyncRequest {
  final String id;
  final String endpoint;
  final String method;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final int retries;

  OfflineSyncRequest({
    required this.id,
    required this.endpoint,
    this.method = 'POST',
    required this.payload,
    required this.timestamp,
    this.retries = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'endpoint': endpoint,
      'method': method,
      'payload': payload,
      'timestamp': timestamp.toIso8601String(),
      'retries': retries,
    };
  }

  factory OfflineSyncRequest.fromMap(Map<String, dynamic> map) {
    return OfflineSyncRequest(
      id: map['id'] ?? '',
      endpoint: map['endpoint'] ?? '',
      method: map['method'] ?? 'POST',
      payload: Map<String, dynamic>.from(map['payload'] ?? {}),
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
      retries: map['retries'] ?? 0,
    );
  }

  OfflineSyncRequest copyWithIncrementedRetry() {
    return OfflineSyncRequest(
      id: id,
      endpoint: endpoint,
      method: method,
      payload: payload,
      timestamp: timestamp,
      retries: retries + 1,
    );
  }
}

class OfflineSyncService {
  static const String _queueKey = 'jyamiti_offline_sync_queue_v1';
  static OfflineSyncService? _instance;
  Timer? _autoSyncTimer;
  bool _isSyncing = false;

  static OfflineSyncService get instance {
    _instance ??= OfflineSyncService._();
    return _instance!;
  }

  OfflineSyncService._();

  // Initialize auto-sync timer (runs every 30 seconds)
  void initAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncPendingRequests();
    });
  }

  // Get all pending offline requests
  Future<List<OfflineSyncRequest>> getPendingRequests() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_queueKey);
      if (raw == null || raw.isEmpty) return [];

      final List<dynamic> list = json.decode(raw);
      return list.map((x) => OfflineSyncRequest.fromMap(x as Map<String, dynamic>)).toList();
    } catch (e) {
      if (kDebugMode) print('Error reading offline sync queue: $e');
      return [];
    }
  }

  // Enqueue a request for offline sync
  Future<void> enqueueRequest(
    String endpoint,
    Map<String, dynamic> payload, {
    String method = 'POST',
  }) async {
    final queue = await getPendingRequests();
    final requestId = '${DateTime.now().millisecondsSinceEpoch}_${queue.length}';
    
    // Avoid duplicate requests for identical endpoint/id if deck saving
    queue.removeWhere((item) =>
        item.endpoint == endpoint &&
        item.payload['id'] != null &&
        item.payload['id'] == payload['id']);

    queue.add(OfflineSyncRequest(
      id: requestId,
      endpoint: endpoint,
      method: method,
      payload: payload,
      timestamp: DateTime.now(),
      retries: 0,
    ));

    await _saveQueue(queue);
    if (kDebugMode) {
      print('📦 Enqueued offline sync request for $endpoint (Queue size: ${queue.length})');
    }
  }

  // Flush and sync pending requests to backend server API
  Future<void> syncPendingRequests() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final queue = await getPendingRequests();
      if (queue.isEmpty) {
        _isSyncing = false;
        return;
      }

      if (kDebugMode) {
        print('🔄 Attempting to sync ${queue.length} offline request(s)...');
      }

      final List<OfflineSyncRequest> remainingQueue = [];

      for (final req in queue) {
        try {
          late dynamic res;
          if (req.method == 'POST') {
            res = await ApiService.post(req.endpoint, req.payload);
          } else if (req.method == 'PUT') {
            res = await ApiService.put(req.endpoint, req.payload);
          } else if (req.method == 'DELETE') {
            res = await ApiService.delete('${req.endpoint}/${req.payload['id']}');
          } else {
            res = await ApiService.post(req.endpoint, req.payload);
          }

          if (res != null && (res.statusCode == 200 || res.statusCode == 201)) {
            if (kDebugMode) {
              print('✅ Synced offline request ${req.id} (${req.endpoint}) successfully!');
            }
          } else if (res != null && res.statusCode >= 400 && res.statusCode < 500) {
            // Discard client-side errors immediately since retrying won't succeed
            if (kDebugMode) {
              print('⚠️ Discarding offline request ${req.id} due to client error ${res.statusCode} (${req.endpoint})');
            }
          } else {
            // Server error or other issue, increment retry and keep in queue if under limit
            final updatedReq = req.copyWithIncrementedRetry();
            if (updatedReq.retries < 10) {
              remainingQueue.add(updatedReq);
            } else {
              if (kDebugMode) {
                print('❌ Discarding offline request ${req.id} after exceeding max retries (${req.endpoint})');
              }
            }
          }
        } catch (e) {
          // Network connection error, increment retry and keep in queue if under limit
          final updatedReq = req.copyWithIncrementedRetry();
          if (updatedReq.retries < 10) {
            remainingQueue.add(updatedReq);
          } else {
            if (kDebugMode) {
              print('❌ Discarding offline request ${req.id} due to network failures and max retries reached: $e');
            }
          }
        }
      }

      await _saveQueue(remainingQueue);
    } catch (e) {
      if (kDebugMode) print('Error during offline sync: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _saveQueue(List<OfflineSyncRequest> queue) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(queue.map((q) => q.toMap()).toList());
    await prefs.setString(_queueKey, jsonStr);
  }
}
