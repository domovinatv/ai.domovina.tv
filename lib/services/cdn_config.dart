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
  static String summaryEnUrl(String ytId) => '$base/data/$ytId/summary.en.json';
  static String articleEnUrl(String ytId) => '$base/data/$ytId/article.en.json';
  static String magisteriumEnUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium.en.json';
  static String magisteriumBatchEnUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_batch.en.json';
  static String magisteriumFullV2EnUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_full_v2.en.json';
  static String diarizedSrtUrl(String ytId) => '$base/data/$ytId/diarized.srt';

  /// Video MP4 — CDN podržava HTTP 206 range requeste za seeking.
  /// Ovo je izvorni codec (može biti AV1/VP9 — ne dekodira se HW svugdje).
  static String videoUrl(String ytId) => '$base/data/$ytId/video.mp4';

  /// H.264 transcode — univerzalno HW-dekodirajuć (Android 4+, svi browseri,
  /// iOS). Pipeline producira ovo paralelno s `video.mp4`. Postoji samo za
  /// epizode koje su prošle transcode korak; vidi [DataService.resolveMedia]
  /// koji probe-a postojanje i fallback-a na [videoUrl] ako 404.
  static String videoH264Url(String ytId) => '$base/data/$ytId/video_h264.mp4';

  /// Probe URL za H.264 postojanje — s cache-busterom da stale 404 (od prije
  /// nego je transcode završio) ne zaglavi fallback na izvorni video.
  /// Playback i dalje koristi čisti [videoH264Url] (immutable cache OK).
  static String videoH264ProbeUrl(String ytId) =>
      '$base/data/$ytId/video_h264.mp4?${_channelCacheBuster()}';

  /// Probe URL za legacy `video.mp4` postojanje (cache-buster zbog 404 cache-a).
  static String videoProbeUrl(String ytId) =>
      '$base/data/$ytId/video.mp4?${_channelCacheBuster()}';

  /// Audio MP3 — AUDIO-ONLY epizode (beamly/transistor kanali bez YouTube
  /// videa, npr. subclub/launched). Pipeline uploada `audio.mp3` (audio/mpeg,
  /// immutable) za epizode kojima je `_yt_matched === false`. Podržava HTTP 206
  /// range requeste (seek). Vidi data_contract.md §8.1 + [DataService.resolveMedia].
  static String audioUrl(String ytId) => '$base/data/$ytId/audio.mp3';

  /// Probe URL za `audio.mp3` postojanje — s cache-busterom (CDN cache-ira 404
  /// 4h, pa stale 404 od prije uploada ne smije zaglaviti detekciju).
  /// Playback koristi čisti [audioUrl] (immutable cache OK).
  static String audioProbeUrl(String ytId) =>
      '$base/data/$ytId/audio.mp3?${_channelCacheBuster()}';

  /// Thumbnail epizode — full-res PNG original (1280×720, tipično ~800 KB).
  ///
  /// Za PRIKAZ radije koristi [CachedThumbnail], koji ovaj URL automatski
  /// zamijeni WebP varijantom primjerenom render-širini (vidi
  /// [thumbnailVariantUrl]) i pada natrag na ovaj PNG ako varijanta ne postoji.
  /// Ovaj URL ostaje kanonski identitet slike i fallback.
  static String thumbnailUrl(String ytId) => '$base/images/$ytId/thumbnail.png';

  /// Širine WebP varijanti koje pipeline generira
  /// (`fetch.domovina.tv/generate_webp_thumbs.js`). Mora ostati sortirano
  /// uzlazno — [pickThumbWidth] se oslanja na to.
  static const List<int> thumbVariantWidths = [320, 640, 1280];

  /// WebP varijanta thumbnaila. [width] mora biti iz [thumbVariantWidths].
  ///
  /// Zašto uopće: PNG original je ~800 KB po epizodi, pa lista od 20 epizoda
  /// povuče ~16 MB. Ista slika kao WebP q80 @320px je ~13 KB — 61× manje.
  /// Varijante su unaprijed generirane i leže na R2 kao obični statični fajlovi
  /// (nema resize servisa u request pathu), immutable, cachirane na CF edgeu.
  static String thumbnailVariantUrl(String ytId, int width) =>
      '$base/images/$ytId/thumb-$width.webp';

  /// Najmanja varijanta koja pokriva [targetPx] fizičkih piksela.
  ///
  /// [targetPx] je render-širina u logičkim pikselima × devicePixelRatio.
  /// Ako ništa nije dovoljno veliko (vrlo širok layout na DPR 3), vraća najveću
  /// — bolje blago skaliranje prema dolje nego 800 KB PNG.
  static int pickThumbWidth(double targetPx) {
    for (final w in thumbVariantWidths) {
      if (w >= targetPx) return w;
    }
    return thumbVariantWidths.last;
  }

  /// Regex za prepoznavanje kanonskog thumbnail URL-a → hvata YouTube ID.
  /// Koristi [CachedThumbnail] da automatski nadogradi URL na WebP varijantu
  /// bez da ijedan call-site mora znati za varijante.
  static final RegExp thumbnailUrlPattern =
      RegExp(r'/images/([A-Za-z0-9_-]{11})/thumbnail\.png$');

  /// Screenshot za dani timestamp ("HH:MM:SS" → "HH-MM-SS.png")
  static String screenshotUrl(String ytId, String timestamp) {
    final ts = timestamp.replaceAll(':', '-');
    return '$base/images/$ytId/screenshots/$ts.png';
  }
}
