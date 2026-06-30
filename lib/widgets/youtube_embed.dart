/// In-app YouTube player — SLUŽBENI YouTube iframe embed (IFrame Player).
///
/// Zašto: naši CDN streamovi (video_h264.mp4) su 360p; YouTube embed daje
/// korisniku punu kvalitetu izvora (do 4K@60) koju mi ne možemo hostati.
/// Koristimo youtube-nocookie.com (privacy-enhanced mode) i službeni embed
/// bez ikakvih modifikacija playera — uklanjanje reklama ili izvlačenje
/// streamova krši YouTube ToS i namjerno NIJE implementirano.
///
/// Web-only (HtmlElementView iframe, bez dependencyja — wasm-safe preko
/// conditional importa). Native ekrani i dalje koriste "Otvori na YouTube".
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'youtube_embed_web.dart'
    if (dart.library.io) 'youtube_embed_stub.dart' as platform;

/// True na webu gdje iframe embed radi; false na native platformama.
bool get youTubeEmbedSupported => platform.supported;

class YouTubeEmbed extends StatelessWidget {
  final String videoId;

  /// Početna pozicija — preuzima se iz native playera pri prebacivanju.
  final int startSeconds;

  const YouTubeEmbed({
    super.key,
    required this.videoId,
    this.startSeconds = 0,
  });

  @override
  Widget build(BuildContext context) {
    return platform.buildYouTubeEmbed(
      videoId: videoId,
      startSeconds: startSeconds,
    );
  }
}

/// Traka ispod videa dok je YouTube mode aktivan — izlaz natrag na native
/// player drži se IZVAN iframe area (pointer eventi nad platform view-om
/// idu iframeu, pa overlay gumbi nisu pouzdani).
class YouTubeModeBar extends StatelessWidget {
  final VoidCallback onExit;

  const YouTubeModeBar({super.key, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.smart_display, size: 16, color: Color(0xFFFF0000)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.mediaYouTubeQualityHint,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: onExit,
            icon: const Icon(Icons.replay, size: 16),
            label: Text(l.mediaNativePlayerLabel),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
