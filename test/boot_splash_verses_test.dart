import 'dart:convert';
import 'dart:io';

import 'package:domovina_ai/screens/tv/widgets/tv_loading_tips.dart';
import 'package:flutter_test/flutter_test.dart';

/// Web boot splash (`web/index.html`) prikazuje nasumičan citat iz istog
/// skupa kao TV splash. Tekst je provjeren na biblija.ks.hr
/// (docs/splash-bible-citations-factcheck.md), pa web kopija ne smije
/// odlutati od Dart izvora: [Mt 10,26-27] + [defaultBibleVerses], doslovno.
void main() {
  test('web splash citati = Mt 10,26-27 + defaultBibleVerses', () {
    final html = File('web/index.html').readAsStringSync();
    final m = RegExp(r'var verses = (\[[\s\S]*?\]);').firstMatch(html);
    expect(m, isNotNull, reason: 'popis citata u web/index.html nije nađen');
    final web = [
      for (final v in jsonDecode(m!.group(1)!) as List) (v[0], v[1]),
    ];

    expect(web.first.$2, 'Matej 10,26-27');
    // Statični citat u HTML-u (preglednik bez JS-a) = prvi s popisa.
    expect(html, contains('<blockquote id="bi-verse-text">${web.first.$1}<'));
    expect(web.skip(1).toList(), [
      for (final v in defaultBibleVerses) (v.text, v.reference),
    ]);
  });
}
