/// Tripwire: klijent nikad ne zove `signInAnonymously`.
///
/// Povod (8.10.2026.): anonimne prijave su ugašene — 99 % korisnika bilo je
/// anonimno uz 3 konverzije, a svaka anonimna sesija je red u `auth.users`.
/// Bez sesije korisnik je gost: javno čita anon ključem, donira gostujućom
/// granom `pinka-contribute`, a sve što traži račun (mjesto na zidu,
/// sponzorski checkout) dobiva `401 login_required` i nudi prijavu.
/// Ugovor: `domovina-api/docs/sponzorski-trenuci-ugovor.md` §9.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/ ne zove signInAnonymously', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (code.contains('signInAnonymously')) {
          hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason: 'Anonimne prijave su ugašene: bez sesije = gost. Ono što traži '
          'račun obradi kroz `PinkaLoginRequired` / `showAuthSheet`.',
    );
  });
}
