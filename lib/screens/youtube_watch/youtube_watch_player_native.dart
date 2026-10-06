import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/open_url.dart';

/// Native (iOS/Android/macOS) player za `/yt/:id` — službeni
/// youtube-nocookie embed u WebViewu, BEZ ikakve izmjene playera.
///
/// Embed se učitava kao HTML s `baseUrl` na našoj domeni: YouTube od 2025.
/// odbija embed bez Referera (greška 152/153 „Video player configuration
/// error"), a WebView s golim `loadRequest` na embed URL ga ne šalje.
///
/// Svaka navigacija IZVAN embed dokumenta (tap na YouTube logo, naslov,
/// „Watch on YouTube") otvara se vanjskim preglednikom ili YouTube
/// aplikacijom, umjesto da WebView postane youtube.com unutar našeg ekrana.
bool get youTubeWatchSupported => true;

class YouTubeWatchPlayer extends StatefulWidget {
  final String videoId;

  const YouTubeWatchPlayer({super.key, required this.videoId});

  @override
  State<YouTubeWatchPlayer> createState() => _YouTubeWatchPlayerState();
}

class _YouTubeWatchPlayerState extends State<YouTubeWatchPlayer> {
  late final WebViewController _controller;

  static const _baseUrl = 'https://domovina.ai/';

  String get _embedUrl => Uri.https(
        'www.youtube-nocookie.com',
        '/embed/${widget.videoId}',
        <String, String>{
          'rel': '0',
          'playsinline': '1',
          'iv_load_policy': '3',
          'hl': 'hr',
          'color': 'white',
        },
      ).toString();

  String get _html => '''
<!doctype html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style>
</head><body>
<iframe src="$_embedUrl"
  allow="autoplay; fullscreen; encrypted-media; picture-in-picture"
  allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>
</body></html>''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            // Dokument koji smo sami učitali (baseUrl) i sve unutar embed
            // iframea ostaje u WebViewu.
            if (request.url.startsWith(_baseUrl) ||
                request.url == 'about:blank' ||
                (uri != null &&
                    uri.host.endsWith('youtube-nocookie.com') &&
                    uri.path.startsWith('/embed/')) ||
                !request.isMainFrame) {
              return NavigationDecision.navigate;
            }
            openUrl(request.url);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(_html, baseUrl: _baseUrl);
  }

  @override
  Widget build(BuildContext context) =>
      WebViewWidget(controller: _controller);
}
