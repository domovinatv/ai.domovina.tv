import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const bool supported = true;

/// Registrirani viewType-ovi — factory se smije registrirati samo jednom.
final Set<String> _registeredViewTypes = <String>{};

Widget buildYouTubeEmbed({
  required String videoId,
  required int startSeconds,
}) {
  final viewType = 'domovina-yt-embed-$videoId-$startSeconds';
  if (_registeredViewTypes.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final src = Uri.https(
        'www.youtube-nocookie.com',
        '/embed/$videoId',
        <String, String>{
          'autoplay': '1',
          if (startSeconds > 0) 'start': '$startSeconds',
          'rel': '0',
          'playsinline': '1',
          'hl': 'hr',
          'color': 'white',
        },
      ).toString();
      final iframe = web.HTMLIFrameElement()
        ..src = src
        ..allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture'
        ..allowFullscreen = true;
      iframe.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%';
      return iframe;
    });
  }
  return HtmlElementView(viewType: viewType);
}
