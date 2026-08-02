import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win;
import 'package:url_launcher/url_launcher.dart';

Widget getInlineYoutubePlayer({required String videoId, required String videoUrl}) {
  if (Platform.isWindows) {
    return _WindowsYoutubePlayer(videoId: videoId, videoUrl: videoUrl);
  }
  return _MobileYoutubePlayer(videoId: videoId);
}

class _MobileYoutubePlayer extends StatefulWidget {
  final String videoId;
  const _MobileYoutubePlayer({required this.videoId});

  @override
  State<_MobileYoutubePlayer> createState() => _MobileYoutubePlayerState();
}

class _MobileYoutubePlayerState extends State<_MobileYoutubePlayer> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        mute: false,
        showFullscreenButton: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayer(controller: _controller);
  }
}

class _WindowsYoutubePlayer extends StatefulWidget {
  final String videoId;
  final String videoUrl;
  const _WindowsYoutubePlayer({required this.videoId, required this.videoUrl});

  @override
  State<_WindowsYoutubePlayer> createState() => _WindowsYoutubePlayerState();
}

class _WindowsYoutubePlayerState extends State<_WindowsYoutubePlayer> {
  final _controller = win.WebviewController();
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initWebview();
  }

  Future<void> _initWebview() async {
    try {
      await _controller.initialize();
      final embedUrl = 'https://app.jyamitimath.com/youtube-embed.html?v=${widget.videoId}';
      await _controller.loadUrl(embedUrl);
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              'Failed to initialize native Windows WebView.',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please ensure Microsoft Edge WebView2 Runtime is installed.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              icon: const Icon(Icons.open_in_browser, color: Colors.white),
              label: const Text('Open in Browser', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                final url = Uri.tryParse(widget.videoUrl);
                if (url != null) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.redAccent),
      );
    }

    return win.Webview(_controller);
  }
}
