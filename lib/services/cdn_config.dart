/// Centralna definicija svih CDN URL-ova za cdn.domovina.ai.
///
/// Svi asseti (JSON podaci, slike, video) loadaju se u runtimeu iz CDN-a
/// na temelju YouTube ID-a epizode — bez lokalnih bundlanih fajlova.
class CdnConfig {
  static const String base = 'https://cdn.domovina.ai';

  // Channel listing files se mijenjaju kako stižu novi videi, ali backend
  // uploader trenutno postavlja Cache-Control: immutable na sve fajlove.
  // Defensive frontend mjera: cache-buster s 5-minutnim bucket-om — dovoljno
  // svjeze da novi video bude vidljiv brzo, dovoljno stabilno da CDN moze
  // servirati istu URL verziju vise klijenata. Per-video JSON (article,
  // summary, info, ...) su pravo immutable pa nemaju cache-buster.
  static String _channelCacheBuster() {
    final bucket = DateTime.now().millisecondsSinceEpoch ~/ 300000;
    return 'v=$bucket';
  }

  // Channels
  static String channelsIndexUrl() =>
      '$base/channels/data/index.json?${_channelCacheBuster()}';
  static String channelUrl(String channelId) =>
      '$base/channels/data/$channelId.json?${_channelCacheBuster()}';
  static String channelAvatarUrl(String channelId) =>
      '$base/channels/images/$channelId/avatar_square.jpg?${_channelCacheBuster()}';
  static String channelCoverUrl(String channelId) =>
      '$base/channels/images/$channelId/avatar_cover.jpg?${_channelCacheBuster()}';

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
  static String magisteriumFullV2Url(String ytId) =>
      '$base/data/$ytId/article.magisterium_full_v2.json';
  static String magisteriumFullV2PromptUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_full_v2_prompt.md';

  // English translation overlays — superset HR + dodana `_en` polja.
  // 404 dok pipeline jos nije producirao prijevod za dani video.
  static String summaryEnUrl(String ytId) =>
      '$base/data/$ytId/summary.en.json';
  static String articleEnUrl(String ytId) =>
      '$base/data/$ytId/article.en.json';
  static String magisteriumEnUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium.en.json';
  static String magisteriumBatchEnUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_batch.en.json';
  static String magisteriumFullV2EnUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_full_v2.en.json';
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
