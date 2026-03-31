/// Model za article.magisterium_full.json — cjelovita Magisterium AI evaluacija
/// cijelog clanka s citatima iz crkvenih dokumenata.
class MagisteriumFullData {
  final String version;
  final String? generatedAt;
  final String? model;
  final String? sourceArticle;
  final String? promptFile;
  final int? promptLengthChars;
  final int overallScore;
  final String scoreInterpretation;
  final String evaluation;
  final List<MagisteriumFullCitation> citations;

  const MagisteriumFullData({
    required this.version,
    this.generatedAt,
    this.model,
    this.sourceArticle,
    this.promptFile,
    this.promptLengthChars,
    required this.overallScore,
    required this.scoreInterpretation,
    required this.evaluation,
    required this.citations,
  });

  factory MagisteriumFullData.fromJson(Map<String, dynamic> json) {
    return MagisteriumFullData(
      version: json['version'] as String? ?? '1.0',
      generatedAt: json['generated_at'] as String?,
      model: json['model'] as String?,
      sourceArticle: json['source_article'] as String?,
      promptFile: json['prompt_file'] as String?,
      promptLengthChars: json['prompt_length_chars'] as int?,
      overallScore: json['overall_score'] as int? ?? 0,
      scoreInterpretation:
          json['score_interpretation'] as String? ?? '',
      evaluation: json['evaluation'] as String? ?? '',
      citations: (json['citations'] as List<dynamic>?)
              ?.map((e) => MagisteriumFullCitation.fromJson(
                  e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class MagisteriumFullCitation {
  final String citedText;
  final String documentTitle;
  final String? documentAuthor;
  final String? documentYear;
  final String? documentReference;
  final String? sourceUrl;

  const MagisteriumFullCitation({
    required this.citedText,
    required this.documentTitle,
    this.documentAuthor,
    this.documentYear,
    this.documentReference,
    this.sourceUrl,
  });

  factory MagisteriumFullCitation.fromJson(Map<String, dynamic> json) {
    return MagisteriumFullCitation(
      citedText: json['cited_text'] as String? ?? '',
      documentTitle: json['document_title'] as String? ?? '',
      documentAuthor: json['document_author'] as String?,
      documentYear: json['document_year'] as String?,
      documentReference: json['document_reference'] as String?,
      sourceUrl: json['source_url'] as String?,
    );
  }
}
