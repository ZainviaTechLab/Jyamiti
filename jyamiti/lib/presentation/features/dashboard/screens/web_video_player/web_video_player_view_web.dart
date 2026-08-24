import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget buildWebVideoPlayerWidget({
  required String blobUrl,
  required String viewId,
}) {
  ui_web.platformViewRegistry.registerViewFactory(
    viewId,
    (int id) {
      final video = web.HTMLVideoElement()
        ..src = blobUrl
        ..controls = true
        ..autoplay = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none'
        ..style.borderRadius = '12px'
        ..style.backgroundColor = '#000000';
      return video;
    },
  );

  return HtmlElementView(viewType: viewId);
}

void openInNewTab(String url) {
  web.window.open(url, '_blank');
}
