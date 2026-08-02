import 'package:flutter/material.dart';

import 'inline_youtube_player_stub.dart'
    if (dart.library.html) 'inline_youtube_player_web.dart'
    if (dart.library.io) 'inline_youtube_player_native.dart';

class InlineYoutubePlayer extends StatelessWidget {
  final String videoId;
  final String videoUrl;

  const InlineYoutubePlayer({
    super.key,
    required this.videoId,
    required this.videoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return getInlineYoutubePlayer(videoId: videoId, videoUrl: videoUrl);
  }
}
