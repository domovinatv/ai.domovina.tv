import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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

  group('PersonMarkBuilder inline rendering', () {
    testWidgets('chip je mergean u isti RichText kao okolni tekst (inline)',
        (tester) async {
      final marked = markPersonMentions(
        'Uvodni tekst o gostu Damiru Stojiću i njegovoj katehezi.',
        'Damir Stojić',
      );
      expect(marked, contains('⟦'));

      await tester.pumpWidget(_Harness(marked));

      // Cijeli paragraf mora biti JEDAN mergani text widget čiji span tree
      // sadrži i okolni tekst i WidgetSpan chipa — to je definicija inline
      // flowa u flutter_markdownu. Da chip nije mergean, paragraf bi bio
      // Wrap s više zasebnih text widgeta (i chip bi "lomio" rečenicu).
      final richTexts = tester
          .widgetList<RichText>(find.byType(RichText))
          .where((rt) => rt.text.toPlainText().contains('Uvodni tekst'))
          .toList();
      expect(richTexts, hasLength(1));

      var hasWidgetSpan = false;
      richTexts.single.text.visitChildren((span) {
        if (span is WidgetSpan) hasWidgetSpan = true;
        return true;
      });
      expect(hasWidgetSpan, isTrue,
          reason: 'chip (WidgetSpan) mora biti unutar merganog paragrafa');

      // Zaobljeni rubovi: Container chipa ima BoxDecoration s borderRadius.
      final chipContainer = tester.widget<Container>(
        find.ancestor(
          of: find.text('Damiru Stojiću'),
          matching: find.byType(Container),
        ),
      );
      final deco = chipContainer.decoration! as BoxDecoration;
      expect(deco.borderRadius, isNotNull);
    });
  });
}

// ---------------------------------------------------------------------------
// Widget test harness: chip mora biti INLINE u paragrafu (mergean u isti
// RichText kao okolni tekst kroz flutter_markdown _mergeInlineChildren), ne
// zaseban blok. Regresija: builder koji vrati obični Text (textSpan == null)
// završi kao zaseban item u Wrap-u → highlight lomi rečenicu u novi red.
// ---------------------------------------------------------------------------

class _Harness extends StatelessWidget {
  final String data;
  const _Harness(this.data);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: MarkdownBody(
          data: data,
          inlineSyntaxes: [PersonMarkSyntax()],
          builders: {
            'personMark': PersonMarkBuilder(
              background: Colors.red,
              foreground: Colors.white,
            ),
          },
        ),
      ),
    );
  }
}
