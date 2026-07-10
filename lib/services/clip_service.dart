/// On-demand chapter clip URLs served by `cutter.domovina.ai` (the standalone
/// `domovina-cutter` service). The cutter lazily cuts an article iteration out
/// of the full episode with ffmpeg, caches it on R2, and 302-redirects warm
/// requests straight to `cdn.domovina.ai`. First hit for a chapter cuts +
/// caches (a few seconds); every hit after is an instant CDN redirect.
///
/// The public contract is keyed by the 1-based `iteration_number` from
/// `article.json` — the SAME chapter index the app already parses into
/// [ArticleIteration.iterationNumber]. No extra metadata to thread through.
///
/// IMPORTANT: never GET/HEAD `cdn.domovina.ai/clips/…` from the client for a
/// possibly-cold clip — `cdn.domovina.ai` caches 404s for 4h, which would then
/// poison the warm redirect target for the whole cache window. Only ever hit
/// `cutter.domovina.ai` (it checks existence through the R2 binding). The size
/// shown in the UI is therefore ESTIMATED from the chapter duration, never
/// fetched.
class ClipService {
  static const _base = 'https://cutter.domovina.ai';

  /// Inline/streamable clip URL (302 → CDN). Pasteable into a message — plays
  /// inline in clients whose size limit allows it (Telegram, iMessage), and
  /// opens/downloads elsewhere.
  static String inlineUrl(String videoId, int chapter) =>
      '$_base/clip/$videoId/$chapter.mp4';

  /// Download URL — the cutter sets `Content-Disposition: attachment` with a
  /// filename derived from the chapter theme.
  static String downloadUrl(String videoId, int chapter) =>
      '$_base/clip/$videoId/$chapter.mp4?dl=1';

  /// The source `video_h264.mp4` runs ~27 KB/s (H.264 crf30 @ 360p + AAC 128k).
  /// Stream-copy clips inherit that rate, so duration → size is a good estimate
  /// (measured: 42.5 min → 71 MB, 18.7 min → 28 MB).
  static const _bytesPerSecond = 27000;

  static int estimatedBytes(int durationSeconds) =>
      durationSeconds * _bytesPerSecond;

  /// Parse "HH:MM:SS" (or "MM:SS") to whole seconds. Returns 0 on malformed
  /// input so the UI degrades to "0 min / ~0 MB" rather than throwing.
  static int hmsToSeconds(String hms) {
    final parts = hms.trim().split(':');
    if (parts.length < 2 || parts.length > 3) return 0;
    var total = 0;
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null) return 0;
      total = total * 60 + v;
    }
    return total;
  }

  /// Duration of a chapter given its `start_time`/`end_time` strings.
  static int durationSeconds(String startTime, String endTime) {
    final d = hmsToSeconds(endTime) - hmsToSeconds(startTime);
    return d > 0 ? d : 0;
  }
}
