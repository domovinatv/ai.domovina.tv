/// Model za article.magisterium_full_v2.json — v2 format Magisterium AI
/// evaluacije cijelog clanka. Struktura identicna v1 plus dodano polje
/// `prompt_version` koje identificira verziju prompt template-a (v2).
///
/// Namjerno standalone, bez fallback-a na v1 ili drugi format.
class MagisteriumFullV2Data {
  final String version;
  final String promptVersion;
  final String? generatedAt;
  final String? model;
  final String? sourceArticle;
  final String? promptFile;
  final int? promptLengthChars;
  final int overallScore;
  final String scoreInterpretation;
  final String? scoreInterpretationEn;
  final String evaluation;
  final String? evaluationEn;
  final List<MagisteriumFullV2Citation> citations;

  const MagisteriumFullV2Data({
    required this.version,
    required this.promptVersion,
    this.generatedAt,
    this.model,
    this.sourceArticle,
    this.promptFile,
    this.promptLengthChars,
    required this.overallScore,
    required this.scoreInterpretation,
    this.scoreInterpretationEn,
    required this.evaluation,
    this.evaluationEn,
    required this.citations,
  });

  factory MagisteriumFullV2Data.fromJson(Map<String, dynamic> json) {
    return MagisteriumFullV2Data(
      version: json['version'] as String? ?? '1.0',
      promptVersion: json['prompt_version'] as String? ?? 'v2',
      generatedAt: json['generated_at'] as String?,
      model: json['model'] as String?,
      sourceArticle: json['source_article'] as String?,
      promptFile: json['prompt_file'] as String?,
      promptLengthChars: json['prompt_length_chars'] as int?,
      overallScore: json['overall_score'] as int? ?? 0,
      scoreInterpretation: json['score_interpretation'] as String? ?? '',
      scoreInterpretationEn: json['score_interpretation_en'] as String?,
      evaluation: json['evaluation'] as String? ?? '',
      evaluationEn: json['evaluation_en'] as String?,
      citations: (json['citations'] as List<dynamic>?)
              ?.map((e) => MagisteriumFullV2Citation.fromJson(
                  e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class MagisteriumFullV2Citation {
  final String citedText;
  final String documentTitle;
  final String? documentAuthor;
  final String? documentYear;
  final String? documentReference;
  final String? sourceUrl;

  const MagisteriumFullV2Citation({
    required this.citedText,
    required this.documentTitle,
    this.documentAuthor,
    this.documentYear,
    this.documentReference,
    this.sourceUrl,
  });

  factory MagisteriumFullV2Citation.fromJson(Map<String, dynamic> json) {
    return MagisteriumFullV2Citation(
      citedText: json['cited_text'] as String? ?? '',
      documentTitle: json['document_title'] as String? ?? '',
      documentAuthor: json['document_author'] as String?,
      documentYear: json['document_year'] as String?,
      documentReference: json['document_reference'] as String?,
      sourceUrl: json['source_url'] as String?,
    );
  }
}
