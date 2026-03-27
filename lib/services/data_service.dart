import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/podcast_info.dart';
import '../models/podcast_summary.dart';
import '../models/podcast_outline.dart';
import '../models/podcast_article.dart';
import '../models/speaker_timeline.dart';

/// Čita JSON assete za konkretni YouTube video ID.
///
/// Ocekivana struktura asseta:
///   assets/data/{youtubeId}/info.json
///   assets/data/{youtubeId}/summary.json
///   assets/data/{youtubeId}/outline.json
///   assets/data/{youtubeId}/article.json
///   assets/images/{youtubeId}/thumbnail.webp  (ili .png)
class DataService {
  final String youtubeId;

  const DataService({required this.youtubeId});

  String _dataPath(String filename) => 'assets/data/$youtubeId/$filename';
  String thumbnailWebpPath() => 'assets/images/$youtubeId/thumbnail.webp';
  String thumbnailPngPath() => 'assets/images/$youtubeId/thumbnail.png';

  Future<PodcastInfo> loadInfo() async {
    final raw = await rootBundle.loadString(_dataPath('info.json'));
    return PodcastInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<PodcastSummary> loadSummary() async {
    final raw = await rootBundle.loadString(_dataPath('summary.json'));
    return PodcastSummary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<PodcastOutline> loadOutline() async {
    final raw = await rootBundle.loadString(_dataPath('outline.json'));
    return PodcastOutline.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<PodcastArticle> loadArticle() async {
    final raw = await rootBundle.loadString(_dataPath('article.json'));
    return PodcastArticle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Ucitaj diariziran SRT i parsiraj u SpeakerTimeline.
  /// Vraca null ako fajl ne postoji.
  Future<SpeakerTimeline?> loadSpeakerTimeline() async {
    try {
      final raw = await rootBundle.loadString(_dataPath('diarized.srt'));
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

/// Svi podaci za jednu podcast epizodu, ucitani iz asseta.
class EpisodeData {
  final String youtubeId;
  final PodcastInfo info;
  final PodcastSummary summary;
  final PodcastOutline outline;
  final PodcastArticle article;
  final SpeakerTimeline? speakerTimeline;

  const EpisodeData({
    required this.youtubeId,
    required this.info,
    required this.summary,
    required this.outline,
    required this.article,
    this.speakerTimeline,
  });

  static Future<EpisodeData> load({required String youtubeId}) async {
    final svc = DataService(youtubeId: youtubeId);
    final results = await Future.wait([
      svc.loadInfo(),
      svc.loadSummary(),
      svc.loadOutline(),
      svc.loadArticle(),
      svc.loadSpeakerTimeline(),
    ]);
    return EpisodeData(
      youtubeId: youtubeId,
      info: results[0] as PodcastInfo,
      summary: results[1] as PodcastSummary,
      outline: results[2] as PodcastOutline,
      article: results[3] as PodcastArticle,
      speakerTimeline: results[4] as SpeakerTimeline?,
    );
  }
}
