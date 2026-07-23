import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Person-needle highlight — inline oznaka spomena osobe u tekstu članka.
///
/// Dolazak s /p/ profila govornika (`?p=<slug>`) označi SVA pojavljivanja
/// imena osobe u markdown sadržaju sekcija: bijeli tekst na brand crvenoj
/// pozadini (kao search-hit highlight). Matching je:
///  - dijakritik-neosjetljiv (isti fold kao `personSlug`): "Stojic" ≡ "Stojić"
///  - case-insensitive
///  - tolerantan na hrvatske padeže prefix-matchom: "Damir Stojić" matcha
///    "Damira Stojića", "Damirom Stojićem" (sufiks do [_suffixTolerance] slova)
///  - sekvencijalan po riječima; za imena s ≥3 tokena pokušava i varijantu bez
///    prvog tokena ("Don Damir Stojić" → "Damir Stojić")
///
/// Mehanika: [markPersonMentions] omota pogotke u `⟦…⟧` delimitere (znakovi
/// koji se realno ne pojavljuju u sadržaju), [PersonMarkSyntax] ih parsira u
/// custom `personMark` inline element, a [PersonMarkBuilder] renderira
/// zaobljeni crveni chip kroz `Text.rich(WidgetSpan(...))`.
///
/// VAŽNO (inline flow): flutter_markdown `_mergeInlineChildren` merga u
/// paragraf SAMO widgete s ne-null `textSpan` (`Text.rich`/`RichText`) —
/// obični `Text('…')` završi kao zaseban item u `Wrap`-u i vizualno lomi
/// rečenicu u novi red. Zato builder MORA vratiti `Text.rich`; unutarnji
/// `WidgetSpan` (baseline-aligned) nosi Container sa zaobljenim rubovima.
/// Chip je atomaran (ne prelama se preko redaka) — imena su kratka pa je to
/// prihvatljiv trade-off za zaobljene rubove.

const String _open = '⟦';
const String _close = '⟧';

/// Maksimalni broj dodatnih slova nakon tokena imena (padežni nastavci:
/// -a, -u, -om, -em, -ićem…).
const int _suffixTolerance = 3;

const Map<String, String> _fold = {
  'č': 'c', 'ć': 'c', 'š': 's', 'ž': 'z', 'đ': 'd',
};

String _foldLower(String s) =>
    s.toLowerCase().split('').map((ch) => _fold[ch] ?? ch).join();

/// Stem tokena za prefix match: bez završnog samoglasnika (deklinacija ga
/// mijenja: "iva"→"ivu"/"ivom"), ali nikad kraći od 2 slova.
String _stem(String token) {
  if (token.length > 2 && 'aeiou'.contains(token[token.length - 1])) {
    return token.substring(0, token.length - 1);
  }
  return token;
}

final RegExp _wordRe = RegExp(r'\p{L}+', unicode: true);

/// Omota sva pojavljivanja imena [personName] u [text] (markdown) u `⟦…⟧`
/// markere. Vraća isti string ako nema pogodaka.
String markPersonMentions(String text, String personName) {
  final spans = _mentionSpans(text, personName);
  if (spans.isEmpty) return text;

  final buf = StringBuffer();
  var cursor = 0;
  for (final (start, end) in spans) {
    buf
      ..write(text.substring(cursor, start))
      ..write(_open)
      ..write(text.substring(start, end))
      ..write(_close);
    cursor = end;
  }
  buf.write(text.substring(cursor));
  return buf.toString();
}

/// True ako [text] sadrži barem jedan spomen imena [personName].
bool hasPersonMention(String text, String personName) =>
    _mentionSpans(text, personName).isNotEmpty;

/// (start, end) rasponi spomena — nepreklapajući, sortirani.
List<(int, int)> _mentionSpans(String text, String personName) {
  // Tokeni imena: samo riječi ≥2 slova (preskoči inicijale).
  final tokens = _wordRe
      .allMatches(personName)
      .map((m) => _foldLower(m.group(0)!))
      .where((t) => t.length >= 2)
      .toList();
  if (tokens.isEmpty) return const [];

  // Kandidat-sekvence, najduža prva: puno ime, pa bez prvog tokena za imena
  // s ≥3 tokena (honorifik "don"/"fra"/"dr" često izostane u tekstu). Jedan
  // usamljeni token (samo prezime) namjerno NE matchamo — previše lažnih
  // pogodaka na čestim imenima.
  final sequences = <List<String>>[
    tokens,
    if (tokens.length >= 3) tokens.sublist(1),
  ].where((s) => s.isNotEmpty).toList();

  final words = _wordRe.allMatches(text).toList();
  final spans = <(int, int)>[];
  var i = 0;
  while (i < words.length) {
    var advanced = false;
    for (final seq in sequences) {
      if (i + seq.length > words.length) continue;
      var ok = true;
      for (var k = 0; k < seq.length; k++) {
        final w = _foldLower(words[i + k].group(0)!);
        final t = seq[k];
        // Deklinacija često ZAMIJENI završni samoglasnik ("Iva"→"Ivu",
        // "Ivom") pa prefix uspoređujemo sa stemom (token bez završnog
        // samoglasnika, min 2 slova); duljinski cap ostaje relativan na
        // puni token da "Ivan(ković)" ne prođe kao "Iva".
        final stem = _stem(t);
        if (!w.startsWith(stem) || w.length > t.length + _suffixTolerance) {
          ok = false;
          break;
        }
      }
      if (ok) {
        spans.add((words[i].start, words[i + seq.length - 1].end));
        i += seq.length;
        advanced = true;
        break;
      }
    }
    if (!advanced) i++;
  }
  return spans;
}

/// Inline syntax za `⟦…⟧` markere iz [markPersonMentions].
class PersonMarkSyntax extends md.InlineSyntax {
  PersonMarkSyntax() : super('$_open([^$_close\n]+)$_close');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('personMark', match[1]!));
    return true;
  }
}

/// Renderira `personMark` element: bijeli tekst na crvenom zaobljenom chipu,
/// inline u rečenici (vidi napomenu o `Text.rich` u headeru datoteke).
class PersonMarkBuilder extends MarkdownElementBuilder {
  final Color background;
  final Color foreground;

  PersonMarkBuilder({required this.background, required this.foreground});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final base = preferredStyle ?? const TextStyle();
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            // Baseline poravnanje: tekst u chipu sjedi na istoj liniji kao
            // okolna rečenica (bez toga chip "pluta" iznad baseline-a).
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                element.textContent,
                style: base.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  // Bez naslijeđenog paragraph height-a (1.65) — chip bi
                  // inače naduo visinu retka u kojem se nalazi.
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
