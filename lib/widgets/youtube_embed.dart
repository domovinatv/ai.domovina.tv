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
import '../services/open_url.dart';
import 'cached_thumbnail.dart';
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

/// In-app YouTube površina s **facade** poster slojem.
///
/// Zašto facade a ne odmah iframe: epizoda u obradi otvara se kao obična
/// stranica, pa bi iframe s `autoplay=1` startao bez korisnikove geste —
/// browser bi ga mutirao (ista politika opisana u CLAUDE.md „Muted autoplay"),
/// a stranica bi svejedno platila ~1 MB YouTube playera. S posterom prvi tap
/// JEST gesta, pa embed krene sa zvukom, a tko ne klikne ne plati ništa.
///
/// Padne li embed (native platforma bez `HtmlElementView`, ili epizoda kojoj
/// je vlasnik isključio ugrađivanje), tap otvori youtube.com u novoj kartici —
/// isti workaround koji je i dosad bio jedina opcija.
class InAppYouTubePlayer extends StatefulWidget {
  final String videoId;

  /// Kanonski CDN thumbnail epizode. Smije biti 404 (epizoda u redu čekanja) —
  /// tada se crta tamna podloga s YouTube ikonom. NIKAD ne prosljeđuj strani
  /// host (`i.ytimg.com`) — [CachedThumbnail] nema `<img>` CORS fallback.
  final String? posterUrl;

  /// `playable_in_embed` iz info.json — false kad je vlasnik isključio
  /// ugrađivanje. Tada nema iframea ni na webu, nego samo vanjska poveznica.
  final bool playableInEmbed;

  final int startSeconds;

  const InAppYouTubePlayer({
    super.key,
    required this.videoId,
    this.posterUrl,
    this.playableInEmbed = true,
    this.startSeconds = 0,
  });

  /// True kad tap doista otvara player UNUTAR aplikacije (web + dopušten
  /// embed). False znači da je gumb zapravo poveznica na youtube.com.
  static bool canEmbed({required bool playableInEmbed}) =>
      youTubeEmbedSupported && playableInEmbed;

  @override
  State<InAppYouTubePlayer> createState() => _InAppYouTubePlayerState();
}

class _InAppYouTubePlayerState extends State<InAppYouTubePlayer> {
  bool _started = false;

  bool get _embeds =>
      InAppYouTubePlayer.canEmbed(playableInEmbed: widget.playableInEmbed);

  void _onTap() {
    if (_embeds) {
      setState(() => _started = true);
    } else {
      openUrl('https://www.youtube.com/watch?v=${widget.videoId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _started
            ? YouTubeEmbed(
                videoId: widget.videoId,
                startSeconds: widget.startSeconds,
              )
            : Material(
                color: Colors.black,
                child: InkWell(
                  onTap: _onTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.posterUrl != null)
                        Opacity(
                          opacity: 0.55,
                          child: CachedThumbnail(
                            url: widget.posterUrl!,
                            fit: BoxFit.cover,
                            errorFallbackBuilder: (_) =>
                                const ColoredBox(color: Colors.black),
                          ),
                        ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 46,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF0000),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _embeds
                                  ? l.episodeWatchInApp
                                  : l.episodeWatchOnYouTube,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
