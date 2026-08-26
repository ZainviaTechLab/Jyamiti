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

  // Waiting-room / "don't auto-join camera+mic to the channel" flow --
  // the room opens straight into a LOCAL-ONLY preview (camera/mic
  // captured for self-view, never published/joined to the actual Agora
  // channel, so it costs nothing and no one else can see or hear it)
  // until the user explicitly taps "Join Now". `_hasJoinedChannel`
  // gates both the UI (preview toolbar vs normal call toolbar) and
  // which teardown path `_handleEndOrLeaveCall` takes.
  bool _hasJoinedChannel = false;
  bool _isJoining = false;

  // Host-only 5-minute no-show safety net -- started the moment the
  // host actually joins (see `_onChannelJoined`), cancelled the moment
  // any remote user is seen (see `_onRemoteUserJoined`). If it fires
  // with no remote user ever having joined, shows a popup and leaves
  // automatically -- see `_handleNoShowTimeout`.
  Timer? _noShowTimer;
  bool _remoteUserSeen = false;
  static const Duration _kNoShowTimeout = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    final channel = widget.meeting['channelName'] ??
        'meet_${DateTime.now().millisecondsSinceEpoch}';
    _viewId = 'agora_meet_frame_${channel}_${DateTime.now().millisecondsSinceEpoch}';

    // Automatically mark meeting as LIVE when host enters -- independent
    // of whether they've actually tapped "Join Now" yet (see
    // `_hasJoinedChannel`'s doc comment): this is about the meeting
    // RECORD's status for listing purposes, not the video call itself.
    if (widget.isHost && widget.meeting['_id'] != null) {
      ParentMeetingService.updateMeetingStatus(
        widget.meeting['_id'].toString(),
        'live',
      ).then((_) {}).catchError((_) => null);
    }

    // The elapsed-time badge only starts once the call actually begins
    // -- see `_onChannelJoined` -- not while still in preview.
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
      unawaited(_initNativeAgoraEnginePreviewOnly());
    }
  }

  /// Native (non-web) counterpart to `_registerAgoraWebIframe` -- sets up
  /// the SAME Agora channel/token via the official `agora_rtc_engine`
  /// plugin instead of an HTML/JS iframe. Camera/mic permissions are
  /// requested explicitly first (required on Android; a safe no-op-ish
  /// call on Windows/macOS/iOS, which prompt via their own OS dialogs
  /// the moment the engine actually touches the device either way).
  ///
  /// Deliberately stops at `startPreview()` -- LOCAL camera/mic capture
  /// for self-view only, never published/joined to the actual channel
  /// (see `_hasJoinedChannel`'s doc comment). `_joinNativeChannel`
  /// (fired by the "Join Now" button) does the actual `joinChannel`.
  Future<void> _initNativeAgoraEnginePreviewOnly() async {
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

      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: appId));

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (mounted) {
              setState(() {
                _hasJoinedChannel = true;
                _isJoining = false;
              });
              _onChannelJoined();
            }
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (mounted) setState(() => _remoteUids.add(remoteUid));
            _onRemoteUserJoined();
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

      _rtcEngine = engine;
      if (mounted) setState(() => _nativeEngineReady = true);
    } catch (e) {
      debugPrint('Native Agora init error: $e');
      if (mounted) {
        setState(() => _nativeMediaError = 'Could not start the video call: $e');
      }
    }
  }

  /// Fired by the "Join Now" button (native path) -- actually joins the
  /// channel using the engine/preview already set up by
  /// `_initNativeAgoraEnginePreviewOnly`.
  Future<void> _joinNativeChannel() async {
    if (_rtcEngine == null || _isJoining || _hasJoinedChannel) return;
    setState(() => _isJoining = true);
    try {
      final String channel = widget.meeting['channelName'] ?? 'test_channel';
      await _rtcEngine!.joinChannel(
        token: _rtcToken ?? '',
        channelId: channel,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      // `_hasJoinedChannel`/`_isJoining` are actually flipped in
      // `onJoinChannelSuccess` above once Agora confirms the join, not
      // here -- this call merely requests it.
    } catch (e) {
      debugPrint('Native join error: $e');
      if (mounted) {
        setState(() {
          _isJoining = false;
          _nativeMediaError = 'Could not join the call: $e';
        });
      }
    }
  }

  /// Fired once the call actually starts (native: `onJoinChannelSuccess`;
  /// web: the iframe's `joined` message -- see `_registerAgoraWebIframe`)
  /// -- shared by both platforms. Starts the elapsed-time badge fresh
  /// from 0 (not from when the room screen first opened, since nothing
  /// was happening during preview) and, for the host only, arms the
  /// 5-minute no-show timer.
  void _onChannelJoined() {
    _timer?.cancel();
    _elapsedSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _elapsedSeconds++);
    });

    if (widget.isHost) {
      _noShowTimer?.cancel();
      _noShowTimer = Timer(_kNoShowTimeout, _handleNoShowTimeout);
    }
  }

  /// Fired the moment any remote participant is seen (native:
  /// `onUserJoined`; web: the iframe's `user_joined` message) --
  /// cancels the no-show timer, since the whole point of it is "did
  /// anyone actually show up."
  void _onRemoteUserJoined() {
    _remoteUserSeen = true;
    _noShowTimer?.cancel();
    _noShowTimer = null;
  }

  /// The 5-minute no-show safety net firing: no remote participant ever
  /// joined this host's class. Shows a popup, then leaves automatically
  /// -- via the same `_performLeave` teardown the normal Leave/End
  /// button uses, just without asking for confirmation first (the
  /// timeout itself already establishes that this class should end).
  Future<void> _handleNoShowTimeout() async {
    if (!mounted || _remoteUserSeen || _isLeaving) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            context.isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('No One Joined', style: TextStyle(color: context.textColor)),
        content: Text(
          'No students joined within 5 minutes, so this class is ending '
          'automatically.',
          style: TextStyle(color: context.textColor70),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) await _performLeave();
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
    let hasNotifiedUserJoined = false;

    AgoraRTC.setLogLevel(3); // warnings only

    // Event listeners are registered here -- immediately after the client
    // is created, well before join()/publish() are ever called -- and NOT
    // inside joinAndPublish() after those awaits. This matters: if the
    // other participant already has published tracks in the channel by
    // the time we join, the SDK can fire "user-published" for their
    // existing track the moment our join() resolves, which can race
    // ahead of (and be missed by) a listener that's only attached after
    // join()+publish() finish awaiting. A plain EventEmitter never
    // replays a missed event, so whoever joins second would be stuck
    // seeing "waiting for other participants" forever while the first
    // joiner (whose listener was already live) sees them fine -- exactly
    // the asymmetric "one side sees both, the other sees no one" bug.
    client.on("user-published", async (user, mediaType) => {
      try {
        await client.subscribe(user, mediaType);
        const count = client.remoteUsers.length + 1;
        updateStatus("👥 " + count + " participant(s) connected");
        if (!hasNotifiedUserJoined) {
          hasNotifiedUserJoined = true;
          window.parent.postMessage({ type: "user_joined" }, "*");
        }

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

    // Local-only camera/mic preview -- captures tracks and plays them
    // locally, but never calls client.join()/client.publish(), so
    // nothing is actually sent to the channel and no one else can see
    // or hear it yet. Runs immediately on load (see the bottom of this
    // script); joinAndPublish() below only fires once Flutter's "Join
    // Now" button posts the joinChannel action.
    async function initPreview() {
      try {
        updateStatus("📹 Requesting Camera & Microphone for preview...");
        try {
          [localTracks.audioTrack, localTracks.videoTrack] =
            await AgoraRTC.createMicrophoneAndCameraTracks(
              { encoderConfig: "speech_standard" },
              { encoderConfig: "720p_1" }
            );

          playVideoWithRetry(localTracks.videoTrack, "local-player", 5);
          updateStatus("✅ Ready -- tap Join Now when you're ready to start.");
        } catch (mediaErr) {
          console.warn("Camera/Mic creation failed, attempting audio only:", mediaErr.message);
          try {
            localTracks.audioTrack = await AgoraRTC.createMicrophoneAudioTrack();
            const avatar = document.getElementById("local-avatar");
            const player = document.getElementById("local-player");
            if (player) player.style.display = "none";
            if (avatar) avatar.style.display = "flex";
            updateStatus("🎙️ Audio Only — Camera access denied or unavailable");
          } catch (audioErr) {
            updateStatus("⚠️ Media error: Check camera & microphone permissions");
          }
        }
      } catch (err) {
        console.error("Agora Preview Error:", err);
        updateStatus("❌ Preview Error: " + (err.message || err));
      }
    }

    // Actually joins the channel and publishes the already-captured
    // preview tracks -- fired once by Flutter's "Join Now" button (see
    // the "joinChannel" message action below), never automatically.
    async function joinAndPublish() {
      try {
        updateStatus("🔑 Connecting to Agora Video Channel: " + CHANNEL + "...");
        await client.join(APP_ID, CHANNEL, TOKEN, null);
        isJoined = true;
        window.parent.postMessage({ type: "joined" }, "*");

        const tracksToPublish = Object.values(localTracks).filter(Boolean);
        if (tracksToPublish.length > 0) {
          await client.publish(tracksToPublish);
        }
        updateStatus("🟢 Live! Waiting for other participants...");
        // Remote-user event listeners are already registered above (right
        // after client creation) -- see the comment there for why they
        // must NOT be attached here, after join()/publish() have already
        // awaited.
      } catch (err) {
        console.error("Agora Join Error:", err);
        updateStatus("❌ Connection Error: " + (err.message || err));
        window.parent.postMessage({ type: "join_failed", error: String(err.message || err) }, "*");
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
      if (data.action === "joinChannel") {
        joinAndPublish();
      }
    });

    // Notify Flutter that JS is ready to receive messages
    window.addEventListener("load", () => {
      window.parent.postMessage({ type: "iframe_ready" }, "*");
    });

    initPreview();
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
      onJoined: () {
        if (!mounted) return;
        setState(() {
          _hasJoinedChannel = true;
          _isJoining = false;
        });
        _onChannelJoined();
      },
      onJoinFailed: (error) {
        if (!mounted) return;
        setState(() => _isJoining = false);
        debugPrint('Web join failed: $error');
      },
      onUserJoined: _onRemoteUserJoined,
    );

    setState(() {});
  }

  /// Fired by the "Join Now" button (web path) -- tells the iframe's JS
  /// to actually join the channel and publish the preview tracks it's
  /// already captured (see `initPreview`/`joinAndPublish` in the JS
  /// above).
  void _joinWebChannel() {
    if (_hasJoinedChannel || _isJoining) return;
    setState(() => _isJoining = true);
    _postIframeMessage({'action': 'joinChannel'});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _noShowTimer?.cancel();
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

    // Still in preview -- never actually joined the channel, so there's
    // nothing real to confirm ending; just tear down local resources and
    // go back.
    if (!_hasJoinedChannel) {
      await _performLeave();
      return;
    }

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
      await _performLeave();
    }
  }

  /// The actual teardown, shared by three callers: the confirmed
  /// Leave/End button, backing out of the preview before ever joining
  /// (no confirmation needed there -- see `_handleEndOrLeaveCall`), and
  /// the 5-minute no-show timeout (`_handleNoShowTimeout`, no
  /// confirmation needed there either -- the timeout itself already
  /// establishes the class should end).
  Future<void> _performLeave() async {
    if (_isLeaving) return;
    setState(() => _isLeaving = true);
    _noShowTimer?.cancel();

    // Update status in DB first (host only)
    if (widget.isHost && widget.meeting['_id'] != null) {
      await ParentMeetingService.updateMeetingStatus(
        widget.meeting['_id'].toString(),
        'ended',
      ).then((_) {}).catchError((_) => null);
    }

    if (kIsWeb) {
      // Tell JS to leave. It will send back 'agora_left' → we pop. Safe
      // even if never actually joined (leaveChannel() itself no-ops if
      // `isJoined` is false, but local tracks still get stopped/closed).
      // Set a fallback timer in case the message never comes back.
      _postIframeMessage({'action': 'leave'});

      // Fallback: pop after 2 seconds even if JS doesn't respond
      Timer(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
    } else {
      // No iframe round-trip to wait for on native -- leave the channel
      // directly, then pop. Safe even if never actually joined
      // (leaveChannel() on an engine that's only previewing, never
      // joined, is a documented no-op rather than an error).
      try {
        await _rtcEngine?.leaveChannel();
        await _rtcEngine?.release();
      } catch (_) {}
      _rtcEngine = null;
      if (mounted) Navigator.pop(context);
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
                    // Preview badge (not joined yet) or Live + Timer badge
                    if (!_hasJoinedChannel)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'PREVIEW',
                          style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      )
                    else
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

              // Bottom Action Controls Toolbar -- preview (waiting room)
              // toolbar before joining, normal call toolbar after.
              if (!_hasJoinedChannel)
                _buildPreviewToolbar()
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
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

  /// Whether local preview (camera/mic captured, not yet joined to the
  /// channel) has actually started -- gates the "Join Now" button so it
  /// can't be tapped before there's an engine/iframe ready to join with.
  bool get _isPreviewReady => kIsWeb ? _iframeReady : _nativeEngineReady;

  /// Waiting-room toolbar shown before the call has actually started --
  /// see `_hasJoinedChannel`'s doc comment. Mute/camera toggles still
  /// work here (local track control only, doesn't need a channel), plus
  /// a "Join Now" button that actually starts the call
  /// (`_joinWebChannel`/`_joinNativeChannel`) and a plain Cancel to back
  /// out without ever joining.
  Widget _buildPreviewToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: const Color(0xFF0F172A),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isHost)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'If no student joins within 5 minutes of starting, this '
                'class will end automatically.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlFab(
                icon: _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: _isMicMuted ? 'Unmute' : 'Mute',
                color: _isMicMuted ? Colors.redAccent : const Color(0xFF334155),
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
              _buildControlFab(
                icon: _isVideoOff
                    ? Icons.videocam_off_rounded
                    : Icons.videocam_rounded,
                label: _isVideoOff ? 'Start Video' : 'Stop Video',
                color: _isVideoOff ? Colors.redAccent : const Color(0xFF334155),
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
              const SizedBox(width: 24),
              TextButton(
                onPressed: _isLeaving ? null : _handleEndOrLeaveCall,
                child: Text(
                  'Cancel',
                  style: TextStyle(color: context.textColor60),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: (_isPreviewReady && !_isJoining && !_isLeaving)
                    ? (kIsWeb ? _joinWebChannel : _joinNativeChannel)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF334155),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isJoining
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.video_call_rounded, size: 20),
                label: Text(
                  _isJoining ? 'Joining...' : 'Join Now',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
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
