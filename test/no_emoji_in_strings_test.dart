/// Tripwire: u korisničkim stringovima nema emojija.
///
/// Povod (15.9.2026.): sweep koji je iz sučelja maknuo `🙏`, `⚙`, `◀▶▲▼` i
/// `⏱`. Emoji u aplikaciji odaje „AI generated" dojam, a ima i tvrdi tehnički
/// razlog: glif ovisi o fontu koji ga na kraju dobije — `🇭🇷` nema glifa u
/// Windows Chromeu, a `⏱` je Pillow tiho nacrtao kao `.notdef` kvadratić na
/// svih 65 759 OG slika (vidi CLAUDE.md, „u OG sliku se ne piše emoji").
///
/// Ikona umjesto emojija: `Icons.*` putuje s aplikacijom i prati `IconTheme`.
///
/// Namjerno DOPUŠTENO (nije emoji, nego tipografija):
/// * `⌘` (U+2318) — znak otisnut na Apple tipki, u oznaci prečice.
/// * `↑ ↓ ← → ↵` — strelice i Return u legendi tipkovnice; imenuju fizičku
///   tipku, pa bi ih ikona učinila manje jasnima, ne više.
/// * `→` i `–` u opisima za prevoditelje (`@key.description`) — to ne vidi
///   korisnik, nego prevoditelj.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Piktografi: emoji blokovi + Misc Symbols + Dingbats + geometrijski trokuti
/// koji se na dijelu platformi podignu u emoji prikaz.
final _pictograph = RegExp(
  '[\u{1F000}-\u{1FAFF}'
  '\u{2600}-\u{27BF}'
  '\u{2B00}-\u{2BFF}'
  '\u{25A0}-\u{25FF}'
  '\u{23E9}-\u{23FA}\u{23F0}\u{23F1}\u{23F2}\u{23F3}'
  '\u{FE0F}]',
  unicode: true,
);

/// Znakovi koji imenuju fizičku tipku — tipografija, ne emoji.
const _allowed = {'⌘', '↑', '↓', '←', '→', '↵'};

Iterable<String> _offenders(String value) =>
    _pictograph.allMatches(value).map((m) => m.group(0)!).where(
          (c) => !_allowed.contains(c),
        );

void main() {
  group('bez emojija u korisničkim stringovima', () {
    for (final arb in ['lib/l10n/app_hr.arb', 'lib/l10n/app_en.arb']) {
      test(arb, () {
        final json =
            jsonDecode(File(arb).readAsStringSync()) as Map<String, dynamic>;
        final bad = <String, String>{};
        json.forEach((key, value) {
          // `@key` blokovi su opisi za prevoditelje, ne korisnički tekst.
          if (key.startsWith('@') || value is! String) return;
          final hits = _offenders(value).toSet();
          if (hits.isNotEmpty) bad[key] = '${hits.join(' ')}  →  "$value"';
        });
        expect(
          bad,
          isEmpty,
          reason: 'Emoji u prijevodu. Zamijeni ikonom (`Icons.*`) na pozivnom '
              'mjestu ili ga izbaci ako uz njega već stoji ikona:\n'
              '${bad.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}',
        );
      });
    }

    test('Dart string literali u lib/', () {
      final bad = <String>[];
      // Literal u jednom retku; komentari (`//`, `///`) su izuzeti jer
      // dokumentiraju stvarnost (npr. „`1` = 👍") i korisnik ih ne vidi.
      final literal = RegExp(r"""('[^'\n]*'|"[^"\n]*")""");
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.contains('/l10n/')) continue; // pokriven ARB testovima
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          for (final m in literal.allMatches(line)) {
            final hits = _offenders(m.group(0)!).toSet();
            if (hits.isNotEmpty) {
              bad.add('${f.path}:${i + 1}  ${hits.join(' ')}  ${line.trim()}');
            }
          }
        }
      }
      expect(bad, isEmpty, reason: 'Emoji u Dart literalu:\n${bad.join('\n')}');
    });
  });
}
