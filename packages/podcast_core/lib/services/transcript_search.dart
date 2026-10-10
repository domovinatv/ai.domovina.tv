import 'dart:convert';

import 'package:http/http.dart' as http;

import 'meili_client.dart';

/// „Pronađi u epizodi" — doslovna pretraga transkripta jedne epizode nad
/// Meili indexom `segments` (1 dokument = 1 SRT segment, točna sekunda).
///
/// Backend i pravila upita žive u `domovina-rag`
/// (`services/mcp/src/tools/find-in-transcript.ts`); ovdje su prenesena tri:
/// padeži ([toWordFormsQuery]), doslovno vs. tipfeler ([classifyMatch]) i
/// `matchingStrategy: "all"` (default "last" odbacuje riječi upita i vraća
/// segmente bez traženog imena).
class TranscriptSearch {
  /// Search-only ključ ograničen na index `segments` (deterministički, siguran
  /// za bundle kao i ključ za `episodes`). Izvor istine:
  /// `domovina-rag/scripts/meili-provision-keys.sh --segments --cloud`.
  static const String _key = String.fromEnvironment(
    'MEILI_SEGMENTS_SEARCH_KEY',
    defaultValue:
        'cfe8897afe72e493878c5e098a54c3d7bee009fab0b2c30e388e086935aaaa9c',
  );

  /// Unutar epizode tražimo iscrpno; više od ovoga se samo prebroji.
  static const int pageSize = 100;

  static final http.Client _http = http.Client();

  static Future<TranscriptSearchResult> search(
    String youtubeId,
    String query, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final effective = toWordFormsQuery(query);
    final resp = await _http
        .post(
          Uri.parse('${MeiliClient.baseUrl}/indexes/segments/search'),
          headers: {
            'Authorization': 'Bearer $_key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'q': effective,
            // YouTube ID je [A-Za-z0-9_-]{11} — navodnik ne može ući u filtar.
            'filter': "youtube_id = '$youtubeId'",
            // page/hitsPerPage daje TOČAN totalHits; sort = kronološki.
            'sort': ['start_sec:asc'],
            'hitsPerPage': pageSize,
            'page': 1,
            'matchingStrategy': 'all',
            'attributesToRetrieve': ['seq', 'start_sec', 'end_sec', 'speaker'],
            'attributesToHighlight': ['text'],
            // Segment zna imati 15+ s govora — isječak oko pogotka je dovoljan.
            'attributesToCrop': ['text'],
            'cropLength': 30,
            'cropMarker': '…',
            'highlightPreTag': '<em>',
            'highlightPostTag': '</em>',
          }),
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw MeiliException('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    // Klasifikacija ide nad POSLANIM upitom: „Matijom" je doslovan pogodak
    // za „Matij", ali ne i za „Matija".
    return TranscriptSearchResult.fromJson(json, query: effective);
  }
}

class TranscriptSearchResult {
  /// Ukupno pogodaka u epizodi (može biti više od [hits]).
  final int totalHits;
  final List<TranscriptHit> hits;

  const TranscriptSearchResult({required this.totalHits, required this.hits});

  factory TranscriptSearchResult.fromJson(
    Map<String, dynamic> json, {
    required String query,
  }) {
    final hits = (json['hits'] as List<dynamic>? ?? const [])
        .map((e) => TranscriptHit.fromJson(e as Map<String, dynamic>, query))
        .toList()
      // `sort` u Meiliju dolazi IZA pravila words/typo, pa tipfeleri stižu na
      // kraju bez obzira na vrijeme. Kronologija se zato slaže ovdje.
      ..sort((a, b) => a.startSec.compareTo(b.startSec));
    return TranscriptSearchResult(
      totalHits: (json['totalHits'] as num?)?.toInt() ?? hits.length,
      hits: hits,
    );
  }

  List<TranscriptHit> get exact => [
        for (final h in hits)
          if (h.exact) h,
      ];

  List<TranscriptHit> get approximate => [
        for (final h in hits)
          if (!h.exact) h,
      ];
}

class TranscriptHit {
  final int seq;
  final double startSec;
  final double endSec;

  /// Ime iz dijarizacije — zna biti krivo, pa ga UI ne smije prikazati kao
  /// tvrdnju „X je rekao".
  final String? speaker;

  /// Tekst segmenta s `<em>…</em>` oko pogođenih dijelova.
  final String formatted;

  /// Svaka riječ upita je doslovno u segmentu (zadnja i kao prefiks). Inače je
  /// pogodak došao samo preko tolerancije tipfelera.
  final bool exact;

  const TranscriptHit({
    required this.seq,
    required this.startSec,
    required this.endSec,
    required this.speaker,
    required this.formatted,
    required this.exact,
  });

  int get second => startSec.floor();

  factory TranscriptHit.fromJson(Map<String, dynamic> json, String query) {
    final fmt = json['_formatted'] as Map<String, dynamic>? ?? const {};
    final text = fmt['text'] as String? ?? json['text'] as String? ?? '';
    final speaker = (json['speaker'] as String?)?.trim();
    return TranscriptHit(
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      startSec: (json['start_sec'] as num?)?.toDouble() ?? 0,
      endSec: (json['end_sec'] as num?)?.toDouble() ?? 0,
      speaker: (speaker == null || speaker.isEmpty) ? null : speaker,
      formatted: text,
      exact: classifyMatch(query, text),
    );
  }
}

final RegExp _trailingVowel = RegExp(r'[aeiou]$', caseSensitive: false);

/// Hrvatski padeži: zadnjoj riječi skini do dva završna samoglasnika dok
/// ostaje ≥ 4 slova. Meili zadnju riječ ionako traži kao prefiks, pa „Matij"
/// pogađa Matija/Matiju/Matijom (tolerancija tipfelera to ne pokriva). Fraza u
/// navodnicima ostaje netaknuta — traži točan slijed riječi.
String toWordFormsQuery(String query) {
  final q = query.trim();
  if (q.contains('"')) return q;
  final words = q.split(RegExp(r'\s+'));
  var last = words.last;
  for (var i = 0; i < 2 && last.length > 4 && _trailingVowel.hasMatch(last); i++) {
    last = last.substring(0, last.length - 1);
  }
  words[words.length - 1] = last;
  return words.join(' ');
}

const _foldFrom = 'čćšžđČĆŠŽĐáàâäéèêëíìîïóòôöúùûüýÿñ';
const _foldTo = 'ccszdCCSZDaaaaeeeeiiiioooouuuuyyn';

String _fold(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = _foldFrom.indexOf(ch);
    b.write(i < 0 ? ch : _foldTo[i]);
  }
  return b.toString().toLowerCase();
}

final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _highlighted =
    RegExp(r'<em>(.+?)</em>([\p{L}\p{N}]*)', unicode: true);

/// Je li segment pogođen doslovno? Meili označi pogođeni dio riječi
/// (`<em>Matij</em>a`), pa se oznaka proširi do cijele riječi i usporedi s
/// riječima upita (bez dijakritike, kao što normalizira i Meili). Zadnja
/// riječ upita smije biti prefiks — tako je Meili i traži. „Matija" →
/// „Marija" je tipfeler, ne pogodak.
bool classifyMatch(String query, String highlighted) {
  final terms = _fold(query.replaceAll('"', ' '))
      .split(_nonWord)
      .where((t) => t.isNotEmpty)
      .toList();
  if (terms.isEmpty) return true;
  final words = [
    for (final m in _highlighted.allMatches(highlighted))
      _fold('${m[1]}${m[2]}'),
  ];
  final isPhrase = query.contains('"');
  for (var i = 0; i < terms.length; i++) {
    final t = terms[i];
    final prefixOk = !isPhrase && i == terms.length - 1;
    if (!words.any((w) => w == t || (prefixOk && w.startsWith(t)))) {
      return false;
    }
  }
  return true;
}

/// `m:ss` ili `h:mm:ss`.
String formatTranscriptTimestamp(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = (sec % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
