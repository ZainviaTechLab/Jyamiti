import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

/// Web implementation: embeds the Agora meeting room as an HTML iframe and
/// registers it as a Flutter platform view.
class MeetingIframeController {
  bool get isSupported => true;

  html.IFrameElement? _iframeElement;

  void create({
    required String viewId,
    required String htmlContent,
    required void Function() onReady,
    required void Function() onLeft,
    void Function()? onUserJoined,
    void Function()? onJoined,
    void Function(String error)? onJoinFailed,
  }) {
    final html.IFrameElement iframeElement = html.IFrameElement()
      ..srcdoc = htmlContent
      ..allow = 'camera; microphone; display-capture; autoplay; fullscreen'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';

    _iframeElement = iframeElement;

    html.window.onMessage.listen((event) {
      final data = event.data;
      if (data is Map) {
        final type = data['type'];
        if (type == 'iframe_ready' || type == 'pong') {
          onReady();
        } else if (type == 'agora_left') {
          onLeft();
        } else if (type == 'user_joined') {
          onUserJoined?.call();
        } else if (type == 'joined') {
          onJoined?.call();
        } else if (type == 'join_failed') {
          onJoinFailed?.call((data['error'] ?? 'Unknown error').toString());
        }
      }
    });

    ui_web.platformViewRegistry.registerViewFactory(
      viewId,
      (int viewId) => iframeElement,
    );
  }

  void postMessage(Map<String, dynamic> data) {
    _iframeElement?.contentWindow?.postMessage(data, '*');
  }

  void dispose() {
    // Nothing extra needed -- the iframe is removed with the widget tree.
  }
}
