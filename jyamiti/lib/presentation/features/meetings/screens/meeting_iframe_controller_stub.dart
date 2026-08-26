/// Non-web fallback for [MeetingIframeController] -- the Agora meeting room
/// is embedded via an HTML iframe, which only exists on the web platform.
/// This stub lets the surrounding screen compile on every other platform
/// (Windows, macOS, Linux, Android, iOS) without pulling in `dart:html`,
/// which isn't available outside web builds.
class MeetingIframeController {
  bool get isSupported => false;

  void create({
    required String viewId,
    required String htmlContent,
    required void Function() onReady,
    required void Function() onLeft,
    void Function()? onUserJoined,
    void Function()? onJoined,
    void Function(String error)? onJoinFailed,
  }) {
    // No-op: nothing to embed on non-web platforms.
  }

  void postMessage(Map<String, dynamic> data) {
    // No-op.
  }

  void dispose() {
    // No-op.
  }
}
