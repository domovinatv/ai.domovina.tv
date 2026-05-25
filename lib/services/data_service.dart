import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/channel_index.dart';
import '../models/channel_detail.dart';
import '../models/podcast_info.dart';
import '../models/podcast_summary.dart';
import '../models/podcast_outline.dart';
import '../models/podcast_article.dart';
import '../models/magisterium_data.dart';
import '../models/magisterium_full_data.dart';
import '../models/magisterium_full_v2_data.dart';
import '../models/speaker_timeline.dart';
import 'cdn_config.dart';

/// Bačen kad info.json za dani YouTube ID ne postoji na CDN-u (HTTP 404).
class VideoNotFoundException implements Exception {
  final String youtubeId;
  const VideoNotFoundException(this.youtubeId);

  @override
  String toString() => 'VideoNotFoundException: $youtubeId';
}

/// Učitava channel index i detail s CDN-a.
class ChannelService {
  static Future<ChannelIndex> loadIndex() async {
    final response = await http.get(Uri.parse(CdnConfig.channelsIndexUrl()));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: channels/index.json');
    }
    return ChannelIndex.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<ChannelDetail> loadChannel(String channelId) async {
    final url = CdnConfig.channelUrl(channelId);
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return ChannelDetail.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }
}

/// Učitava podatke za konkretni YouTube video ID s CDN-a (cdn.domovina.ai).
class DataService {
  final String youtubeId;

  const DataService({required this.youtubeId});

  Future<String> _fetch(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return response.body;
  }

  Future<PodcastInfo> loadInfo() async {
    final url = CdnConfig.infoUrl(youtubeId);
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 404) throw VideoNotFoundException(youtubeId);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return PodcastInfo.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Summary — vraca null ako fajl ne postoji (AI pipeline jos nije gotov).
  /// Prave HTTP greske propagira dalje.
  Future<PodcastSummary?> loadSummary() async {
    final url = CdnConfig.summaryUrl(youtubeId);
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return PodcastSummary.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Outline — vraca null ako fajl ne postoji (AI pipeline jos nije gotov).
  Future<PodcastOutline?> loadOutline() async {
    final url = CdnConfig.outlineUrl(youtubeId);
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return PodcastOutline.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Article — vraca null ako fajl ne postoji (AI pipeline jos nije gotov).
  Future<PodcastArticle?> loadArticle() async {
    final url = CdnConfig.articleUrl(youtubeId);
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return PodcastArticle.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Magisterium teološko obogaćivanje — opcionalno (nije obavezan asset).
  Future<MagisteriumData?> loadMagisterium() async {
    try {
      final raw = await _fetch(CdnConfig.magisteriumUrl(youtubeId));
      return MagisteriumData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Magisterium batch varijanta — opcionalno.
  Future<MagisteriumData?> loadMagisteriumBatch() async {
    try {
      final raw = await _fetch(CdnConfig.magisteriumBatchUrl(youtubeId));
      return MagisteriumData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Magisterium full evaluacija (Magisterium AI API) — opcionalno.
  Future<MagisteriumFullData?> loadMagisteriumFull() async {
    try {
      final raw = await _fetch(CdnConfig.magisteriumFullUrl(youtubeId));
      return MagisteriumFullData.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Magisterium full prompt (markdown) — opcionalno.
  Future<String?> loadMagisteriumFullPrompt() async {
    try {
      return await _fetch(CdnConfig.magisteriumFullPromptUrl(youtubeId));
    } catch (_) {
      return null;
    }
  }

  /// Magisterium full v2 evaluacija — novi format s `prompt_version`. Opcionalno.
  Future<MagisteriumFullV2Data?> loadMagisteriumFullV2() async {
    try {
      final raw = await _fetch(CdnConfig.magisteriumFullV2Url(youtubeId));
      return MagisteriumFullV2Data.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Magisterium full v2 prompt (markdown) — opcionalno.
  Future<String?> loadMagisteriumFullV2Prompt() async {
    try {
      return await _fetch(CdnConfig.magisteriumFullV2PromptUrl(youtubeId));
    } catch (_) {
      return null;
    }
  }

  /// Vraća CDN URL videa — podržava HTTP 206 range requeste za seeking.
  String resolveVideoUri() => CdnConfig.videoUrl(youtubeId);

  /// Ucitaj diariziran SRT i parsiraj u SpeakerTimeline.
  /// Vraća null ako fajl ne postoji (nije obavezan asset).
  Future<SpeakerTimeline?> loadSpeakerTimeline() async {
    try {
      final raw = await _fetch(CdnConfig.diarizedSrtUrl(youtubeId));
      return _parseSrt(raw);
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// SRT parser
// ---------------------------------------------------------------------------

final _tsRegex = RegExp(
  r'(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3})',
);
final _speakerRegex = RegExp(r'^\[(\w+)\]');

int _srtTimeToMs(int h, int m, int s, int ms) =>
    h * 3600000 + m * 60000 + s * 1000 + ms;

SpeakerTimeline _parseSrt(String raw) {
  final segments = <SpeakerSegment>[];
  final blocks = raw.trim().split(RegExp(r'\r?\n\s*\r?\n'));

  for (final block in blocks) {
    final lines = block.trim().split(RegExp(r'\r?\n'));
    if (lines.length < 3) continue;

    final tsMatch = _tsRegex.firstMatch(lines[1]);
    if (tsMatch == null) continue;

    final startMs = _srtTimeToMs(
      int.parse(tsMatch.group(1)!),
      int.parse(tsMatch.group(2)!),
      int.parse(tsMatch.group(3)!),
      int.parse(tsMatch.group(4)!),
    );
    final endMs = _srtTimeToMs(
      int.parse(tsMatch.group(5)!),
      int.parse(tsMatch.group(6)!),
      int.parse(tsMatch.group(7)!),
      int.parse(tsMatch.group(8)!),
    );

    final text = lines.sublist(2).join(' ').trimLeft();
    final speakerMatch = _speakerRegex.firstMatch(text);
    if (speakerMatch == null) continue;

    segments.add(SpeakerSegment(
      startMs: startMs,
      endMs: endMs,
      speakerId: speakerMatch.group(1)!,
    ));
  }

  return SpeakerTimeline(segments: segments);
}

/// Svi podaci za jednu podcast epizodu, ucitani s CDN-a.
///
/// `info` i `videoUri` su uvijek prisutni — to su minimum za reprodukciju.
/// Ostali AI-generirani asseti (`summary`, `outline`, `article`, magisterium*,
/// speakerTimeline) su nullable jer pipeline zna kasniti za par sati/dana
/// nakon sto se video pojavi na YouTube-u. Screens trebaju gracefully
/// renderirati basic view (samo player + osnovne info) kad ovih nema.
class EpisodeData {
  final String youtubeId;
  final PodcastInfo info;
  final PodcastSummary? summary;
  final PodcastOutline? outline;
  final PodcastArticle? article;
  final MagisteriumData? magisterium;
  final MagisteriumData? magisteriumBatch;
  final MagisteriumFullData? magisteriumFull;
  final String? magisteriumFullPrompt;
  final MagisteriumFullV2Data? magisteriumFullV2;
  final String? magisteriumFullV2Prompt;
  final SpeakerTimeline? speakerTimeline;
  final String videoUri;

  const EpisodeData({
    required this.youtubeId,
    required this.info,
    this.summary,
    this.outline,
    this.article,
    this.magisterium,
    this.magisteriumBatch,
    this.magisteriumFull,
    this.magisteriumFullPrompt,
    this.magisteriumFullV2,
    this.magisteriumFullV2Prompt,
    this.speakerTimeline,
    required this.videoUri,
  });

  /// True kad AI pipeline (clanak) nije produkcijski gotov. UI tada pokazuje
  /// samo player + basic info i opcionalno YouTube chapters iz info.json.
  bool get hasAiContent => article != null;

  /// Helper za naslov: preferira HR summary, fallback na YouTube info.title.
  String get displayTitle {
    final hr = summary?.summary.titleHr;
    if (hr != null && hr.isNotEmpty) return hr;
    return info.title;
  }

  /// All available Magisterium variants as (label, data) pairs.
  List<(String, MagisteriumData)> get magisteriumVariants {
    return [
      if (magisterium != null) ('Po sekciji', magisterium!),
      if (magisteriumBatch != null) ('Po bloku', magisteriumBatch!),
    ];
  }

  /// Preferred (first available) Magisterium data for inline enrichment.
  MagisteriumData? get magisteriumPrimary =>
      magisteriumBatch ?? magisterium;

  static Future<EpisodeData> load({required String youtubeId}) async {
    final svc = DataService(youtubeId: youtubeId);
    final results = await Future.wait([
      svc.loadInfo(),           // 0 — required (VideoNotFoundException ako 404)
      svc.loadSummary(),        // 1 — nullable (404 → null)
      svc.loadOutline(),        // 2 — nullable
      svc.loadArticle(),        // 3 — nullable
      svc.loadMagisterium(),    // 4
      svc.loadMagisteriumBatch(), // 5
      svc.loadSpeakerTimeline(),  // 6
      svc.loadMagisteriumFull(),  // 7
      svc.loadMagisteriumFullPrompt(), // 8
      svc.loadMagisteriumFullV2(),     // 9
      svc.loadMagisteriumFullV2Prompt(), // 10
    ]);
    return EpisodeData(
      youtubeId: youtubeId,
      info: results[0] as PodcastInfo,
      summary: results[1] as PodcastSummary?,
      outline: results[2] as PodcastOutline?,
      article: results[3] as PodcastArticle?,
      magisterium: results[4] as MagisteriumData?,
      magisteriumBatch: results[5] as MagisteriumData?,
      speakerTimeline: results[6] as SpeakerTimeline?,
      magisteriumFull: results[7] as MagisteriumFullData?,
      magisteriumFullPrompt: results[8] as String?,
      magisteriumFullV2: results[9] as MagisteriumFullV2Data?,
      magisteriumFullV2Prompt: results[10] as String?,
      videoUri: svc.resolveVideoUri(),
    );
  }

  /// Progressive loader — reports per-asset status via [onProgress].
  /// Assets load in parallel; callback fires as each completes.
  static Future<EpisodeData> loadWithProgress({
    required String youtubeId,
    required void Function(String asset, bool done, bool ok) onProgress,
  }) async {
    final svc = DataService(youtubeId: youtubeId);

    Future<T> track<T>(String name, Future<T> future) async {
      onProgress(name, false, true);
      try {
        final result = await future;
        onProgress(name, true, true);
        return result;
      } catch (e) {
        onProgress(name, true, false);
        rethrow;
      }
    }

    Future<T?> trackOptional<T>(String name, Future<T?> future) async {
      onProgress(name, false, true);
      try {
        final result = await future;
        onProgress(name, true, result != null);
        return result;
      } catch (_) {
        onProgress(name, true, false);
        return null;
      }
    }

    // Start all in parallel — info je jedini required, AI asseti su nullable
    // (404 → null = pipeline jos nije obradio video).
    final infoF = track('Info', svc.loadInfo());
    final summaryF = trackOptional('Sažetak', svc.loadSummary());
    final outlineF = trackOptional('Poglavlja', svc.loadOutline());
    final articleF = trackOptional('Članak', svc.loadArticle());
    final magF = trackOptional('Magisterium', svc.loadMagisterium());
    final magBatchF =
        trackOptional('Magisterium batch', svc.loadMagisteriumBatch());
    final magFullF =
        trackOptional('Magisterium full', svc.loadMagisteriumFull());
    final magPromptF =
        trackOptional('Magisterium prompt', svc.loadMagisteriumFullPrompt());
    final magFullV2F =
        trackOptional('Magisterium v2', svc.loadMagisteriumFullV2());
    final magV2PromptF = trackOptional(
        'Magisterium v2 prompt', svc.loadMagisteriumFullV2Prompt());
    final srtF = trackOptional('Transkript', svc.loadSpeakerTimeline());

    // Await all (required ones may throw)
    final info = await infoF;
    final summary = await summaryF;
    final outline = await outlineF;
    final article = await articleF;
    final mag = await magF;
    final magBatch = await magBatchF;
    final magFull = await magFullF;
    final magPrompt = await magPromptF;
    final magFullV2 = await magFullV2F;
    final magV2Prompt = await magV2PromptF;
    final srt = await srtF;

    return EpisodeData(
      youtubeId: youtubeId,
      info: info,
      summary: summary,
      outline: outline,
      article: article,
      magisterium: mag,
      magisteriumBatch: magBatch,
      magisteriumFull: magFull,
      magisteriumFullPrompt: magPrompt,
      magisteriumFullV2: magFullV2,
      magisteriumFullV2Prompt: magV2Prompt,
      speakerTimeline: srt,
      videoUri: svc.resolveVideoUri(),
    );
  }
}
