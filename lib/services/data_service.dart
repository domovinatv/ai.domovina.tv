import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/podcast_info.dart';
import '../models/podcast_summary.dart';
import '../models/podcast_outline.dart';
import '../models/podcast_article.dart';
import '../models/magisterium_data.dart';
import '../models/speaker_timeline.dart';
import 'cdn_config.dart';

/// Bačen kad info.json za dani YouTube ID ne postoji na CDN-u (HTTP 404).
class VideoNotFoundException implements Exception {
  final String youtubeId;
  const VideoNotFoundException(this.youtubeId);

  @override
  String toString() => 'VideoNotFoundException: $youtubeId';
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

  Future<PodcastSummary> loadSummary() async {
    final raw = await _fetch(CdnConfig.summaryUrl(youtubeId));
    return PodcastSummary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<PodcastOutline> loadOutline() async {
    final raw = await _fetch(CdnConfig.outlineUrl(youtubeId));
    return PodcastOutline.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<PodcastArticle> loadArticle() async {
    final raw = await _fetch(CdnConfig.articleUrl(youtubeId));
    return PodcastArticle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
class EpisodeData {
  final String youtubeId;
  final PodcastInfo info;
  final PodcastSummary summary;
  final PodcastOutline outline;
  final PodcastArticle article;
  final MagisteriumData? magisterium;
  final SpeakerTimeline? speakerTimeline;
  final String videoUri;

  const EpisodeData({
    required this.youtubeId,
    required this.info,
    required this.summary,
    required this.outline,
    required this.article,
    this.magisterium,
    this.speakerTimeline,
    required this.videoUri,
  });

  static Future<EpisodeData> load({required String youtubeId}) async {
    final svc = DataService(youtubeId: youtubeId);
    final results = await Future.wait([
      svc.loadInfo(),
      svc.loadSummary(),
      svc.loadOutline(),
      svc.loadArticle(),
      svc.loadMagisterium(),
      svc.loadSpeakerTimeline(),
    ]);
    return EpisodeData(
      youtubeId: youtubeId,
      info: results[0] as PodcastInfo,
      summary: results[1] as PodcastSummary,
      outline: results[2] as PodcastOutline,
      article: results[3] as PodcastArticle,
      magisterium: results[4] as MagisteriumData?,
      speakerTimeline: results[5] as SpeakerTimeline?,
      videoUri: svc.resolveVideoUri(),
    );
  }
}
