import 'package:podcast_core/services/transcript_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toWordFormsQuery (padeži)', () {
    test('zadnjoj riječi skida do dva završna samoglasnika', () {
      expect(toWordFormsQuery('Matija'), 'Matij');
      expect(toWordFormsQuery('Petar Buljan'), 'Petar Buljan');
      expect(toWordFormsQuery('Gospa'), 'Gosp');
      expect(toWordFormsQuery('Isusa'), 'Isus');
    });

    test('ne skraćuje ispod 4 slova', () {
      expect(toWordFormsQuery('Ivo'), 'Ivo');
      expect(toWordFormsQuery('Ivana'), 'Ivan');
    });

    test('dira samo zadnju riječ', () {
      expect(toWordFormsQuery('sveta Marija'), 'sveta Marij');
    });

    test('fraza u navodnicima ostaje netaknuta', () {
      expect(toWordFormsQuery('"za vrijeme rata"'), '"za vrijeme rata"');
    });
  });

  group('classifyMatch', () {
    test('prefiks zadnje riječi je doslovan pogodak', () {
      expect(classifyMatch('Matij', '<em>Matij</em>a, hoćeš ti'), isTrue);
      expect(classifyMatch('Matij', 'sa <em>Matij</em>om, sa'), isTrue);
    });

    test('tipfeler nije doslovan („Matija" → „Marija")', () {
      expect(classifyMatch('Matij', 'Isus i <em>Marij</em>a!'), isFalse);
    });

    test('dijakritika se ne računa', () {
      expect(classifyMatch('Caljkusic', '<em>Čaljkušić</em> kaže'), isTrue);
    });

    test('fraza traži svaku riječ cijelu', () {
      expect(
        classifyMatch('"za vrijeme"', '<em>za</em> <em>vrijeme</em> rata'),
        isTrue,
      );
      expect(
        classifyMatch('"za vrijem"', '<em>za</em> <em>vrijem</em>e rata'),
        isFalse,
      );
    });
  });

  test('rezultat je kronološki i dijeli doslovne od približnih', () {
    final r = TranscriptSearchResult.fromJson({
      'totalHits': 3,
      'hits': [
        {
          'seq': 24,
          'start_sec': 117.49,
          'end_sec': 120.57,
          'speaker': 'Ante',
          '_formatted': {'text': '<em>Matij</em>a, hoćeš'},
        },
        {
          'seq': 169,
          'start_sec': 1396.62,
          'end_sec': 1414.2,
          'speaker': null,
          '_formatted': {'text': 'sa <em>Matij</em>om'},
        },
        // Meili tipfelere vraća na kraju bez obzira na `sort`.
        {
          'seq': 30,
          'start_sec': 146.88,
          'end_sec': 159.93,
          'speaker': '',
          '_formatted': {'text': 'Isus i <em>Marij</em>a!'},
        },
      ],
    }, query: 'Matij');

    expect(r.totalHits, 3);
    expect(r.hits.map((h) => h.second), [117, 146, 1396]);
    expect(r.exact.map((h) => h.seq), [24, 169]);
    expect(r.approximate.map((h) => h.seq), [30]);
    expect(r.hits[1].speaker, isNull);
  });

  test('formatTranscriptTimestamp', () {
    expect(formatTranscriptTimestamp(117), '1:57');
    expect(formatTranscriptTimestamp(5963), '1:39:23');
  });
}
