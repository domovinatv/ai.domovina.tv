import 'package:flutter/material.dart';

/// Cover-art prikaz za audio-only epizode — zamjenjuje crnu media_kit video
/// površinu (nema video frame-ova). Prikazuje kvadratni artwork (channel
/// avatar) centriran na tamnoj podlozi + diskretnu "Audio" oznaku.
///
/// [artUrl] mora biti CORS-safe (CDN channel avatar je `access-control-allow-
/// origin: *`); ne prosljeđuj transistorcdn `info.thumbnail` jer pod `--wasm`
/// dekoderu treba CORS pa bi pukao. Null → fallback ikona.
class AudioPoster extends StatelessWidget {
  final String? artUrl;

  const AudioPoster({super.key, this.artUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasArt = artUrl != null && artUrl!.isNotEmpty;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: hasArt
                ? AspectRatio(
                    aspectRatio: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          artUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _fallbackIcon(theme),
                        ),
                      ),
                    ),
                  )
                : _fallbackIcon(theme),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.graphic_eq, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Audio',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
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

  Widget _fallbackIcon(ThemeData theme) => Center(
    child: Icon(Icons.podcasts, size: 56, color: Colors.white.withAlpha(120)),
  );
}
