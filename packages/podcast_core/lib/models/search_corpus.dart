/// `channels/data/search.json` — tekst za lokalnu pretragu (sažetak, teme,
/// govornici) koji skraćeni listing kanala (v2) više ne nosi.
///
/// Zašto odvojeno: ta tri polja su 60 % listinga (izmjereno 8.10.2026.:
/// 3,2 od 5,4 MB compact JSON-a), a trebaju samo pretrazi i sponzorskom
/// izlogu. Listinzi bez njih padaju na 0,19 MB brotli; korpus (~0,66 MB)
/// se učitava tek kad ga nešto zatraži. Vidi
/// `docs/2026-10-08-brzina-ucitavanja-naslovnice.md` (P2).
///
/// **Ugovor (v1):**
/// ```json
/// {"version": 1, "generated_at": "…",
///  "episodes": {"<youtube_id>": {"a": "sažetak", "t": ["tema"], "s": ["govornik"]}}}
/// ```
/// Svako polje je opcionalno. `s` su imena govornika (`suggested_name`).
class SearchCorpus {
  static const int supportedVersion = 1;

  final Map<String, SearchText> byId;

  const SearchCorpus(this.byId);

  /// `null` za nepoznatu verziju ili neočekivan oblik.
  static SearchCorpus? tryParse(Map<String, dynamic> json) {
    if ((json['version'] as num?)?.toInt() != supportedVersion) return null;
    final raw = json['episodes'];
    if (raw is! Map<String, dynamic>) return null;
    return SearchCorpus({
      for (final e in raw.entries)
        if (e.value is Map<String, dynamic>)
          e.key: SearchText.fromJson(e.value as Map<String, dynamic>),
    });
  }
}

class SearchText {
  final String? abstract;
  final List<String> topics;
  final List<String> speakers;

  const SearchText({this.abstract, this.topics = const [], this.speakers = const []});

  factory SearchText.fromJson(Map<String, dynamic> json) => SearchText(
        abstract: json['a'] as String?,
        topics: [for (final t in json['t'] as List? ?? const []) if (t is String) t],
        speakers: [for (final t in json['s'] as List? ?? const []) if (t is String) t],
      );
}
