import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/widgets/person_needle_highlight.dart';

void main() {
  group('markPersonMentions', () {
    test('osnovni match nominativa', () {
      final out = markPersonMentions(
        'Gost je bio Damir Stojić na tribini.',
        'Damir Stojić',
      );
      expect(out, 'Gost je bio ⟦Damir Stojić⟧ na tribini.');
    });

    test('padežni oblici (genitiv/instrumental) se matchaju', () {
      expect(
        hasPersonMention('Razgovor s Damirom Stojićem.', 'Damir Stojić'),
        isTrue,
      );
      expect(
        hasPersonMention('Poruka Damira Stojića mladima.', 'Damir Stojić'),
        isTrue,
      );
    });

    test('dijakritik-neosjetljivo u oba smjera', () {
      expect(
        hasPersonMention('don Damir Stojic je rekao', 'Don Damir Stojić'),
        isTrue,
      );
      expect(
        hasPersonMention('don Damir Stojić je rekao', 'Don Damir Stojic'),
        isTrue,
      );
    });

    test('ime s honorifikom matcha i bez njega u tekstu', () {
      expect(
        hasPersonMention(
          'Svećenik Damir Stojić drži katehezu.',
          'Don Damir Stojić',
        ),
        isTrue,
      );
    });

    test('samo prezime NIJE match (premalo signala)', () {
      expect(hasPersonMention('Stojić je rekao.', 'Damir Stojić'), isFalse);
    });

    test('predugi sufiks nije match (Ivan != Ivanković)', () {
      expect(
        hasPersonMention('Marko Ivanković je došao.', 'Marko Ivan'),
        isFalse,
      );
    });

    test('više spomena — svi označeni, bez preklapanja', () {
      final out = markPersonMentions(
        'Iva Kraljević je rekla da je Ivu Kraljević pozvala.',
        'Iva Kraljević',
      );
      expect(out.split('⟦').length - 1, 2);
      expect(out.split('⟧').length - 1, 2);
    });

    test('bez pogodka vraća isti string', () {
      const text = 'Nitko poznat nije spomenut.';
      expect(markPersonMentions(text, 'Damir Stojić'), same(text));
    });
  });
}
