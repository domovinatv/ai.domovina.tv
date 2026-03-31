/// Centralna definicija svih CDN URL-ova za cdn.domovina.ai.
///
/// Svi asseti (JSON podaci, slike, video) loadaju se u runtimeu iz CDN-a
/// na temelju YouTube ID-a epizode — bez lokalnih bundlanih fajlova.
class CdnConfig {
  static const String base = 'https://cdn.domovina.ai';

  // Channels
  static String channelsIndexUrl() => '$base/channels/data/index.json';
  static String channelUrl(String channelId) =>
      '$base/channels/data/$channelId.json';
  static String channelAvatarUrl(String channelId) =>
      '$base/channels/images/$channelId/avatar_square.jpg';
  static String channelCoverUrl(String channelId) =>
      '$base/channels/images/$channelId/avatar_cover.jpg';

  // JSON podaci
  static String infoUrl(String ytId) => '$base/data/$ytId/info.json';
  static String summaryUrl(String ytId) => '$base/data/$ytId/summary.json';
  static String outlineUrl(String ytId) => '$base/data/$ytId/outline.json';
  static String articleUrl(String ytId) => '$base/data/$ytId/article.json';
  static String magisteriumUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium.json';
  static String magisteriumBatchUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_batch.json';
  static String magisteriumFullUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_full.json';
  static String magisteriumFullPromptUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_full_prompt.md';
  static String diarizedSrtUrl(String ytId) => '$base/data/$ytId/diarized.srt';

  /// Video MP4 — CDN podržava HTTP 206 range requeste za seeking
  static String videoUrl(String ytId) => '$base/data/$ytId/video.mp4';

  /// Thumbnail epizode
  static String thumbnailUrl(String ytId) => '$base/images/$ytId/thumbnail.png';

  /// Screenshot za dani timestamp ("HH:MM:SS" → "HH-MM-SS.png")
  static String screenshotUrl(String ytId, String timestamp) {
    final ts = timestamp.replaceAll(':', '-');
    return '$base/images/$ytId/screenshots/$ts.png';
  }
}
