import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/podcast_info.dart';
import '../models/podcast_summary.dart';
import '../models/podcast_outline.dart';
import '../models/podcast_article.dart';

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
}

/// Svi podaci za jednu podcast epizodu, ucitani iz asseta.
class EpisodeData {
  final String youtubeId;
  final PodcastInfo info;
  final PodcastSummary summary;
  final PodcastOutline outline;
  final PodcastArticle article;

  const EpisodeData({
    required this.youtubeId,
    required this.info,
    required this.summary,
    required this.outline,
    required this.article,
  });

  static Future<EpisodeData> load({required String youtubeId}) async {
    final svc = DataService(youtubeId: youtubeId);
    final results = await Future.wait([
      svc.loadInfo(),
      svc.loadSummary(),
      svc.loadOutline(),
      svc.loadArticle(),
    ]);
    return EpisodeData(
      youtubeId: youtubeId,
      info: results[0] as PodcastInfo,
      summary: results[1] as PodcastSummary,
      outline: results[2] as PodcastOutline,
      article: results[3] as PodcastArticle,
    );
  }
}
