import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../services/parent_meeting_service.dart';

// The Agora meeting room is embedded via an HTML iframe, which only exists
// on web -- conditionally import the real dart:html-based controller on web
// and a no-op stub everywhere else, so this screen compiles on every
// platform (Windows/macOS/Linux/Android/iOS) without pulling in dart:html.
import 'meeting_iframe_controller_stub.dart'
    if (dart.library.html) 'meeting_iframe_controller_web.dart';

class ParentMeetingRoomScreen extends StatefulWidget {
  final Map<String, dynamic> meeting;
  final bool isHost;

  const ParentMeetingRoomScreen({
    super.key,
    required this.meeting,
    this.isHost = false,
  });

  @override
  State<ParentMeetingRoomScreen> createState() =>
      _ParentMeetingRoomScreenState();
}

class _ParentMeetingRoomScreenState extends State<ParentMeetingRoomScreen> {
  bool _isMicMuted = false;
  bool _isVideoOff = false;
  bool _isScreenSharing = false;
  bool _isHandRaised = false;
  int _elapsedSeconds = 0;
  Timer? _timer;
  late String _viewId;
  final MeetingIframeController _iframeController = MeetingIframeController();
  bool _iframeReady = false;
  bool _isLeaving = false;

  String? _rtcToken;

  // Native (Windows/Android/iOS/macOS) video path -- the web build keeps
  // using the Agora Web SDK iframe above unchanged; this is the `!kIsWeb`
  // counterpart, using the official agora_rtc_engine plugin instead.
  RtcEngine? _rtcEngine;
  bool _nativeEngineReady = false;
  final Set<int> _remoteUids = {};
  String? _nativeMediaError;

  @override
  void initState() {
    super.initState();
    final channel = widget.meeting['channelName'] ??
        'meet_${DateTime.now().millisecondsSinceEpoch}';
    _viewId = 'agora_meet_frame_${channel}_${DateTime.now().millisecondsSinceEpoch}';

    // Automatically mark meeting as LIVE when host enters
    if (widget.isHost && widget.meeting['_id'] != null) {
      ParentMeetingService.updateMeetingStatus(
        widget.meeting['_id'].toString(),
        'live',
      ).then((_) {}).catchError((_) => null);
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });

    _initAgoraTokenAndIframe();
  }

  Future<void> _initAgoraTokenAndIframe() async {
    final String channel = widget.meeting['channelName'] ?? 'test_channel';
    String? token;
    try {
      token = await ParentMeetingService.getRtcToken(
        channelName: channel,
        isHost: widget.isHost,
      );
    } catch (e) {
      debugPrint('Token fetch error: $e');
    }
    _rtcToken = token;
    if (!mounted) return;
    if (kIsWeb) {
      _registerAgoraWebIframe();
    } else {
      unawaited(_initNativeAgoraEngine());
    }
  }

  /// Native (non-web) counterpart to `_registerAgoraWebIframe` -- joins
  /// the SAME Agora channel/token via the official `agora_rtc_engine`
  /// plugin instead of an HTML/JS iframe. Camera/mic permissions are
  /// requested explicitly first (required on Android; a safe no-op-ish
  /// call on Windows/macOS/iOS, which prompt via their own OS dialogs
  /// the moment the engine actually touches the device either way).
  Future<void> _initNativeAgoraEngine() async {
    try {
      final statuses = await [Permission.camera, Permission.microphone].request();
      final bool granted = statuses.values.every(
        (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
      );
      if (!granted) {
        if (mounted) {
          setState(
            () => _nativeMediaError =
                'Camera/microphone permission was not granted.',
          );
        }
        return;
      }

      final String appId =
          widget.meeting['agoraAppId'] ?? '2bd28ff5ea124b5982b6ef930c49998d';
      final String channel = widget.meeting['channelName'] ?? 'test_channel';

      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: appId));

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (mounted) setState(() => _nativeEngineReady = true);
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (mounted) setState(() => _remoteUids.add(remoteUid));
          },
          onUserOffline: (connection, remoteUid, reason) {
            if (mounted) setState(() => _remoteUids.remove(remoteUid));
          },
          onError: (err, msg) {
            debugPrint('Agora native engine error: $err $msg');
          },
        ),
      );

      await engine.enableVideo();
      await engine.startPreview();
      await engine.joinChannel(
        token: _rtcToken ?? '',
        channelId: channel,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );

      _rtcEngine = engine;
    } catch (e) {
      debugPrint('Native Agora init error: $e');
      if (mounted) {
        setState(() => _nativeMediaError = 'Could not start the video call: $e');
      }
    }
  }

  void _postIframeMessage(Map<String, dynamic> data) {
    if (_iframeReady) {
      _iframeController.postMessage(data);
    }
  }

  void _registerAgoraWebIframe() {
    final String channel = widget.meeting['channelName'] ?? 'test_channel';
    final String appId =
        widget.meeting['agoraAppId'] ?? '2bd28ff5ea124b5982b6ef930c49998d';
    final String hostName = widget.meeting['hostName'] ?? 'Host';
    final String roleName =
        widget.isHost ? 'Host ($hostName)' : 'Parent / Participant';
    final String tokenJs =
        _rtcToken != null ? '"$_rtcToken"' : 'null';

    // HTML source code for interactive Agora RTC Web Video Calling Engine
    final String htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Agora Parent Meeting</title>
  <script src="https://download.agora.io/sdk/release/AgoraRTC_N-4.22.0.js"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #0B0F19;
      color: #F8FAFC;
      height: 100vh;
      width: 100vw;
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }
    #status-banner {
      background: rgba(99, 102, 241, 0.15);
      border-bottom: 1px solid rgba(99, 102, 241, 0.3);
      color: #818CF8;
      padding: 8px 16px;
      font-size: 13px;
      font-weight: 600;
      text-align: center;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      min-height: 36px;
    }
    #video-grid {
      flex: 1;
      display: flex;
      flex-wrap: wrap;
      gap: 16px;
      padding: 16px;
      align-items: center;
      justify-content: center;
      overflow-y: auto;
    }
    .video-card {
      position: relative;
      background: #1E293B;
      border-radius: 16px;
      overflow: hidden;
      flex: 1 1 340px;
      max-width: 640px;
      height: 100%;
      max-height: 480px;
      min-height: 240px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.5);
      border: 1.5px solid rgba(255,255,255,0.1);
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .player {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }
    .name-tag {
      position: absolute;
      bottom: 12px;
      left: 12px;
      background: rgba(15, 23, 42, 0.85);
      backdrop-filter: blur(8px);
      padding: 6px 14px;
      border-radius: 10px;
      font-size: 13px;
      font-weight: 600;
      color: #FFF;
      display: flex;
      align-items: center;
      gap: 8px;
      border: 1px solid rgba(255,255,255,0.15);
      z-index: 10;
    }
    .status-badge {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #10B981;
    }
    .video-off-avatar {
      display: none;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 10px;
      color: #94A3B8;
      width: 100%;
      height: 100%;
      position: absolute;
    }
    .avatar-circle {
      width: 70px;
      height: 70px;
      border-radius: 50%;
      background: #334155;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 28px;
      color: #FFF;
      font-weight: bold;
    }
  </style>
</head>
<body>
  <div id="status-banner">
    <span id="status-text">⏳ Initializing Agora Video Room & Requesting Camera/Microphone...</span>
  </div>

  <div id="video-grid">
    <div class="video-card" id="local-player-card">
      <div id="local-player" class="player"></div>
      <div id="local-avatar" class="video-off-avatar">
        <div class="avatar-circle">📹</div>
        <span>Camera Muted</span>
      </div>
      <div class="name-tag">
        <span class="status-badge"></span>
        <span>You ($roleName)</span>
      </div>
    </div>
  </div>

  <script>
    const APP_ID = "$appId";
    const CHANNEL = "$channel";
    const TOKEN = $tokenJs;

    let client = AgoraRTC.createClient({ mode: "rtc", codec: "vp8" });
    let localTracks = { videoTrack: null, audioTrack: null };
    let isJoined = false;
    let isLeaving = false;

    AgoraRTC.setLogLevel(3); // warnings only

    function updateStatus(text) {
      const el = document.getElementById("status-text");
      if (el) el.innerText = text;
    }

    // Retry playing a video track on a container - handles timing issues
    function playVideoWithRetry(track, containerId, attempts) {
      const container = document.getElementById(containerId);
      if (!container) {
        if (attempts > 0) {
          setTimeout(() => playVideoWithRetry(track, containerId, attempts - 1), 200);
        }
        return;
      }
      try {
        track.play(containerId);
      } catch(e) {
        if (attempts > 0) {
          setTimeout(() => playVideoWithRetry(track, containerId, attempts - 1), 200);
        }
      }
    }

    async function initAgora() {
      try {
        updateStatus("🔑 Connecting to Agora Video Channel: " + CHANNEL + "...");
        await client.join(APP_ID, CHANNEL, TOKEN, null);
        isJoined = true;
        updateStatus("📹 Channel Connected! Requesting Camera & Microphone...");

        try {
          [localTracks.audioTrack, localTracks.videoTrack] =
            await AgoraRTC.createMicrophoneAndCameraTracks(
              { encoderConfig: "speech_standard" },
              { encoderConfig: "720p_1" }
            );

          playVideoWithRetry(localTracks.videoTrack, "local-player", 5);
          await client.publish(Object.values(localTracks).filter(Boolean));
          updateStatus("🟢 Live! Waiting for other participants...");
        } catch (mediaErr) {
          console.warn("Camera/Mic creation failed, attempting audio only:", mediaErr.message);
          try {
            localTracks.audioTrack = await AgoraRTC.createMicrophoneAudioTrack();
            await client.publish([localTracks.audioTrack]);
            const avatar = document.getElementById("local-avatar");
            const player = document.getElementById("local-player");
            if (player) player.style.display = "none";
            if (avatar) avatar.style.display = "flex";
            updateStatus("🎙️ Audio Only — Camera access denied or unavailable");
          } catch (audioErr) {
            updateStatus("⚠️ Media error: Check camera & microphone permissions");
          }
        }

        // Handle remote users joining & publishing video/audio
        client.on("user-published", async (user, mediaType) => {
          try {
            await client.subscribe(user, mediaType);
            const count = client.remoteUsers.length + 1;
            updateStatus("👥 " + count + " participant(s) connected");

            if (mediaType === "video") {
              const remoteContainerId = "player-" + user.uid;
              if (!document.getElementById("card-" + user.uid)) {
                const grid = document.getElementById("video-grid");
                const card = document.createElement("div");
                card.className = "video-card";
                card.id = "card-" + user.uid;
                card.innerHTML = \`<div id="\${remoteContainerId}" class="player"></div>
                  <div class="name-tag">
                    <span class="status-badge"></span>
                    <span>Participant (\${user.uid})</span>
                  </div>\`;
                grid.appendChild(card);
              }
              // Use retry to handle DOM rendering delay
              playVideoWithRetry(user.videoTrack, remoteContainerId, 8);
            }
            if (mediaType === "audio") {
              user.audioTrack.play();
            }
          } catch(subErr) {
            console.error("Subscribe error:", subErr);
          }
        });

        // Re-play video if remote user republishes
        client.on("user-unpublished", (user, mediaType) => {
          if (mediaType === "video") {
            const card = document.getElementById("card-" + user.uid);
            if (card) card.remove();
          }
        });

        client.on("user-left", (user) => {
          const card = document.getElementById("card-" + user.uid);
          if (card) card.remove();
          updateStatus("🟢 Meeting Live — Waiting for participants...");
        });

        client.on("connection-state-change", (curState, prevState, reason) => {
          console.log("Connection state:", prevState, "->", curState, reason);
          if (curState === "DISCONNECTED" && !isLeaving) {
            updateStatus("⚠️ Connection lost. Reconnecting...");
          }
        });

      } catch (err) {
        console.error("Agora Init Error:", err);
        updateStatus("❌ Connection Error: " + (err.message || err));
      }
    }

    async function leaveChannel() {
      if (isLeaving) return;
      isLeaving = true;
      updateStatus("👋 Leaving meeting...");
      try {
        for (let trackName in localTracks) {
          const track = localTracks[trackName];
          if (track) {
            track.stop();
            track.close();
          }
        }
        localTracks = { videoTrack: null, audioTrack: null };
        if (isJoined) {
          await client.leave();
          isJoined = false;
        }
      } catch(e) {
        console.warn("Leave error (ignored):", e);
      }
      // Signal Flutter that JS leave is complete
      window.parent.postMessage({ type: "agora_left" }, "*");
    }

    // Listen for messages from Flutter controls
    window.addEventListener("message", function(event) {
      const data = event.data;
      if (!data || typeof data !== "object") return;

      if (data.action === "ping") {
        window.parent.postMessage({ type: "pong" }, "*");
        return;
      }
      if (data.action === "toggleAudio") {
        if (localTracks.audioTrack) {
          const mute = !!data.mute;
          localTracks.audioTrack.setEnabled(!mute);
        }
      }
      if (data.action === "toggleVideo") {
        if (localTracks.videoTrack) {
          const off = !!data.off;
          localTracks.videoTrack.setEnabled(!off);
          const avatar = document.getElementById("local-avatar");
          const player = document.getElementById("local-player");
          if (off) {
            if (player) player.style.display = "none";
            if (avatar) avatar.style.display = "flex";
          } else {
            if (player) player.style.display = "block";
            if (avatar) avatar.style.display = "none";
            // Re-play in case track was re-enabled after DOM change
            if (localTracks.videoTrack) {
              playVideoWithRetry(localTracks.videoTrack, "local-player", 5);
            }
          }
        }
      }
      if (data.action === "leave") {
        leaveChannel();
      }
    });

    // Notify Flutter that JS is ready to receive messages
    window.addEventListener("load", () => {
      window.parent.postMessage({ type: "iframe_ready" }, "*");
    });

    initAgora();
  </script>
</body>
</html>
    ''';

    _iframeController.create(
      viewId: _viewId,
      htmlContent: htmlContent,
      onReady: () {
        if (!mounted) return;
        setState(() => _iframeReady = true);
      },
      onLeft: () {
        // JS confirmed it left — safe to pop the screen
        if (mounted && !_isLeaving) {
          _isLeaving = true;
          Navigator.pop(context);
        }
      },
    );

    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (kIsWeb) {
      // Only send leave if we're not already in the leave flow
      if (!_isLeaving) {
        _iframeController.postMessage({'action': 'leave'});
      }
      _iframeController.dispose();
    } else {
      // Fire-and-forget -- the screen is being torn down regardless, no
      // UI left to react to these completing.
      _rtcEngine?.leaveChannel();
      _rtcEngine?.release();
    }
    super.dispose();
  }

  Future<void> _handleEndOrLeaveCall() async {
    if (_isLeaving) return;
    final bool isHost = widget.isHost;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isHost ? 'End Parent Meeting?' : 'Leave Meeting?',
          style: TextStyle(color: context.textColor),
        ),
        content: Text(
          isHost
              ? 'This will end the meeting for all parents and participants.'
              : 'Are you sure you want to leave the parent meeting call?',
          style: TextStyle(color: context.textColor70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isHost ? 'End Meeting' : 'Leave'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isLeaving = true);

      // Update status in DB first (host only)
      if (isHost && widget.meeting['_id'] != null) {
        await ParentMeetingService.updateMeetingStatus(
          widget.meeting['_id'].toString(),
          'ended',
        ).then((_) {}).catchError((_) => null);
      }

      if (kIsWeb) {
        // Tell JS to leave. It will send back 'agora_left' → we pop.
        // Set a fallback timer in case the message never comes back.
        _postIframeMessage({'action': 'leave'});

        // Fallback: pop after 2 seconds even if JS doesn't respond
        Timer(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        // No iframe round-trip to wait for on native -- leave the
        // channel directly, then pop.
        try {
          await _rtcEngine?.leaveChannel();
          await _rtcEngine?.release();
        } catch (_) {}
        _rtcEngine = null;
        if (mounted) Navigator.pop(context);
      }
    }
  }

  /// Native (`!kIsWeb`) counterpart to the web iframe's video grid --
  /// local preview tile first, then one tile per remote participant
  /// (`_remoteUids`, kept in sync by `_initNativeAgoraEngine`'s event
  /// handlers).
  Widget _buildNativeVideoArea() {
    if (_nativeMediaError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            _nativeMediaError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
      );
    }
    if (!_nativeEngineReady || _rtcEngine == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF6366F1)),
            SizedBox(height: 16),
            Text(
              'Connecting to video room...',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    final String hostName = widget.meeting['hostName'] ?? 'Host';
    final String roleName =
        widget.isHost ? 'Host ($hostName)' : 'Parent / Participant';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: [
          _buildNativeVideoTile(
            child: AgoraVideoView(
              controller: VideoViewController(
                rtcEngine: _rtcEngine!,
                canvas: const VideoCanvas(uid: 0),
              ),
            ),
            label: 'You ($roleName)',
            showAvatarInstead: _isVideoOff,
          ),
          for (final uid in _remoteUids)
            _buildNativeVideoTile(
              child: AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _rtcEngine!,
                  canvas: VideoCanvas(uid: uid),
                  connection: RtcConnection(
                    channelId: widget.meeting['channelName'] ?? '',
                  ),
                ),
              ),
              label: 'Participant ($uid)',
            ),
        ],
      ),
    );
  }

  Widget _buildNativeVideoTile({
    required Widget child,
    required String label,
    bool showAvatarInstead = false,
  }) {
    return Container(
      width: 340,
      height: 260,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: showAvatarInstead
                ? Container(
                    color: const Color(0xFF1E293B),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.videocam_off_rounded,
                          color: Color(0xFF94A3B8),
                          size: 32,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Camera Muted',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  )
                : child,
          ),
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.meeting['title'] ?? 'Parent Meeting';
    final batchName = widget.meeting['batchName'] ?? 'Batch';
    final hostName = widget.meeting['hostName'] ?? 'Tutor';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _handleEndOrLeaveCall();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF334155)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.video_camera_front_rounded,
                        color: Color(0xFF6366F1),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$batchName • Host: $hostName',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Live indicator + Timer Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(_elapsedSeconds),
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Video Frame (Agora Web Stream)
              Expanded(
                child: _rtcToken == null
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                                color: Color(0xFF6366F1)),
                            SizedBox(height: 16),
                            Text(
                              'Connecting to video room...',
                              style: TextStyle(color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      )
                    : !kIsWeb
                    ? _buildNativeVideoArea()
                    : HtmlElementView(viewType: _viewId),
              ),

              // Bottom Action Controls Toolbar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                color: const Color(0xFF0F172A),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Mute Mic Button
                    _buildControlFab(
                      icon: _isMicMuted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      label: _isMicMuted ? 'Unmute' : 'Mute',
                      color: _isMicMuted
                          ? Colors.redAccent
                          : const Color(0xFF334155),
                      onTap: () {
                        setState(() => _isMicMuted = !_isMicMuted);
                        if (kIsWeb) {
                          _postIframeMessage({
                            'action': 'toggleAudio',
                            'mute': _isMicMuted,
                          });
                        } else {
                          _rtcEngine?.muteLocalAudioStream(_isMicMuted);
                        }
                      },
                    ),
                    const SizedBox(width: 16),

                    // Camera Toggle Button
                    _buildControlFab(
                      icon: _isVideoOff
                          ? Icons.videocam_off_rounded
                          : Icons.videocam_rounded,
                      label: _isVideoOff ? 'Start Video' : 'Stop Video',
                      color: _isVideoOff
                          ? Colors.redAccent
                          : const Color(0xFF334155),
                      onTap: () {
                        setState(() => _isVideoOff = !_isVideoOff);
                        if (kIsWeb) {
                          _postIframeMessage({
                            'action': 'toggleVideo',
                            'off': _isVideoOff,
                          });
                        } else {
                          _rtcEngine?.muteLocalVideoStream(_isVideoOff);
                        }
                      },
                    ),
                    const SizedBox(width: 16),

                    // Screen Share / Raise Hand Button
                    if (widget.isHost) ...[
                      _buildControlFab(
                        icon: Icons.screen_share_rounded,
                        label: _isScreenSharing
                            ? 'Stop Share'
                            : 'Screen Share',
                        color: _isScreenSharing
                            ? const Color(0xFF10B981)
                            : const Color(0xFF334155),
                        onTap: () {
                          setState(() =>
                              _isScreenSharing = !_isScreenSharing);
                        },
                      ),
                      const SizedBox(width: 16),
                    ] else ...[
                      // Raise Hand (Parent/Participant Only)
                      _buildControlFab(
                        icon: Icons.back_hand_rounded,
                        label:
                            _isHandRaised ? 'Hand Raised' : 'Raise Hand',
                        color: _isHandRaised
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF334155),
                        onTap: () {
                          setState(() => _isHandRaised = !_isHandRaised);
                        },
                      ),
                      const SizedBox(width: 16),
                    ],

                    // End Call / Leave Call Button
                    _buildControlFab(
                      icon: Icons.call_end_rounded,
                      label: widget.isHost ? 'End Call' : 'Leave',
                      color: Colors.redAccent,
                      isMainEnd: true,
                      onTap: _isLeaving ? () {} : _handleEndOrLeaveCall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlFab({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isMainEnd = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: isMainEnd ? 60 : 50,
            height: isMainEnd ? 60 : 50,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: isMainEnd ? 26 : 22,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
