/// Model za .article.magisterium.json — teološko obogaćivanje Magisterium AI
class MagisteriumData {
  final String version;
  final DateTime generatedAt;
  final String model;
  final String sourceArticle;
  final int? overallScore;
  final String? scoreInterpretation;
  final List<MagisteriumScoreBreakdown> scoreBreakdown;
  final int totalConcerns;
  final List<MagisteriumIteration> iterations;

  const MagisteriumData({
    required this.version,
    required this.generatedAt,
    required this.model,
    required this.sourceArticle,
    required this.overallScore,
    required this.scoreInterpretation,
    required this.scoreBreakdown,
    required this.totalConcerns,
    required this.iterations,
  });

  factory MagisteriumData.fromJson(Map<String, dynamic> json) {
    return MagisteriumData(
      version: json['version'] as String? ?? '1.0',
      generatedAt: DateTime.parse(json['generated_at'] as String),
      model: json['model'] as String? ?? 'magisterium-1',
      sourceArticle: json['source_article'] as String? ?? '',
      overallScore: json['overall_score'] as int?,
      scoreInterpretation: json['score_interpretation'] as String?,
      scoreBreakdown: (json['score_breakdown'] as List<dynamic>? ?? [])
          .map((e) => MagisteriumScoreBreakdown.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalConcerns: json['total_concerns'] as int? ?? 0,
      iterations: (json['iterations'] as List<dynamic>? ?? [])
          .map((e) => MagisteriumIteration.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Lookup magisterium result by section's screenshot_timestamp.
  SectionMagisterium? forTimestamp(String timestamp) {
    for (final iter in iterations) {
      for (final sec in iter.sections) {
        if (sec.screenshotTimestamp == timestamp) return sec.magisterium;
      }
    }
    return null;
  }
}

class MagisteriumScoreBreakdown {
  final int iteration;
  final String theme;
  final int? score;

  const MagisteriumScoreBreakdown({
    required this.iteration,
    required this.theme,
    required this.score,
  });

  factory MagisteriumScoreBreakdown.fromJson(Map<String, dynamic> json) {
    return MagisteriumScoreBreakdown(
      iteration: json['iteration'] as int,
      theme: json['theme'] as String,
      score: json['score'] as int?,
    );
  }
}

class MagisteriumIteration {
  final int iterationNumber;
  final int? iterationScore;
  final String theme;
  final List<MagisteriumSectionEntry> sections;

  const MagisteriumIteration({
    required this.iterationNumber,
    required this.iterationScore,
    required this.theme,
    required this.sections,
  });

  factory MagisteriumIteration.fromJson(Map<String, dynamic> json) {
    return MagisteriumIteration(
      iterationNumber: json['iteration_number'] as int,
      iterationScore: json['iteration_score'] as int?,
      theme: json['theme'] as String? ?? '',
      sections: (json['sections'] as List<dynamic>? ?? [])
          .map((e) => MagisteriumSectionEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MagisteriumSectionEntry {
  final String subtitle;
  final String screenshotTimestamp;
  final SectionMagisterium? magisterium;

  const MagisteriumSectionEntry({
    required this.subtitle,
    required this.screenshotTimestamp,
    required this.magisterium,
  });

  factory MagisteriumSectionEntry.fromJson(Map<String, dynamic> json) {
    final mag = json['magisterium'];
    return MagisteriumSectionEntry(
      subtitle: json['subtitle'] as String? ?? '',
      screenshotTimestamp: json['screenshot_timestamp'] as String? ?? '',
      magisterium: mag != null && mag is Map<String, dynamic>
          ? SectionMagisterium.fromJson(mag)
          : null,
    );
  }
}

class SectionMagisterium {
  final int? score;
  final String assessment;
  final List<String> concerns;
  final String enrichment;
  final List<MagisteriumCitation> citations;

  const SectionMagisterium({
    required this.score,
    required this.assessment,
    required this.concerns,
    required this.enrichment,
    required this.citations,
  });

  factory SectionMagisterium.fromJson(Map<String, dynamic> json) {
    return SectionMagisterium(
      score: json['score'] as int?,
      assessment: json['assessment'] as String? ?? '',
      concerns: (json['concerns'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      enrichment: json['enrichment'] as String? ?? '',
      citations: (json['citations'] as List<dynamic>? ?? [])
          .map((e) => MagisteriumCitation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MagisteriumCitation {
  final String citedText;
  final String documentTitle;
  final String documentAuthor;
  final String documentYear;
  final String documentReference;
  final String sourceUrl;

  const MagisteriumCitation({
    required this.citedText,
    required this.documentTitle,
    required this.documentAuthor,
    required this.documentYear,
    required this.documentReference,
    required this.sourceUrl,
  });

  factory MagisteriumCitation.fromJson(Map<String, dynamic> json) {
    return MagisteriumCitation(
      citedText: json['cited_text'] as String? ?? '',
      documentTitle: json['document_title'] as String? ?? '',
      documentAuthor: json['document_author'] as String? ?? '',
      documentYear: json['document_year']?.toString() ?? '',
      documentReference: json['document_reference'] as String? ?? '',
      sourceUrl: json['source_url'] as String? ?? '',
    );
  }
}
