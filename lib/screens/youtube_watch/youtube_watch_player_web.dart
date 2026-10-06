import 'package:flutter/widgets.dart';

import '../../widgets/youtube_embed.dart';

/// Web player za `/yt/:id` — isti službeni iframe kao [YouTubeEmbed]. Pod
/// našim COEP-om radi samo uz `credentialless` (Chrome/Edge); ondje gdje ga
/// nema ([youTubeEmbedSupported] == false) ekran nudi youtube.com.
bool get youTubeWatchSupported => youTubeEmbedSupported;

class YouTubeWatchPlayer extends StatelessWidget {
  final String videoId;

  const YouTubeWatchPlayer({super.key, required this.videoId});

  @override
  Widget build(BuildContext context) => YouTubeEmbed(videoId: videoId);
}
