import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/models/search_corpus.dart';
import 'package:podcast_core/services/channel_cache.dart';

/// Skraćeni listing kanala (v2) i `search.json` — vidi `SearchCorpus` i
/// `docs/2026-10-08-brzina-ucitavanja-naslovnice.md` (P2). Klijent mora čitati
/// i v1 i v2: native buildovi iz storea žive mjesecima.
void main() {
  test('v2 listing: bitmask zastavice, brojčana verzija, bez teksta', () {
    final d = ChannelDetail.fromJson({
      'version': 2,
      'id': 'hnb',
      'name': 'HNB',
      'videos': [
        {'id': 'a', 'title': 'A', 'duration_seconds': 6006, 'p': 8 | 16},
      ],
    });
    final v = d.videos.single;
    expect(d.version, '2');
    expect(v.pipeline!.hasArticle, isTrue);
    expect(v.pipeline!.hasMagisterium, isTrue);
    expect(v.pipeline!.hasTranscript, isFalse);
    expect(v.abstract_, isNull);
  });

  test('durationDisplay: pipelineov oblik ima prednost, inače se računa', () {
    ChannelVideo v(int? secs, [String? shown]) => ChannelVideo(
        id: 'x', title: 'x', durationSeconds: secs, durationDisplay: shown);
    expect(v(1214).durationDisplay, '20:14');
    expect(v(6006).durationDisplay, '1:40:06');
    expect(v(59).durationDisplay, '0:59');
    expect(v(6006, 'zadano').durationDisplay, 'zadano');
    expect(v(null).durationDisplay, isNull);
    expect(v(0).durationDisplay, isNull);
  });

  test('v1 listing i dalje radi (pipeline objekt, duration_display)', () {
    final v = ChannelVideo.fromJson({
      'id': 'a',
      'title': 'A',
      'duration_display': '50:41',
      'abstract': 'sažetak',
      'pipeline': {'has_article': true},
    });
    expect(v.durationDisplay, '50:41');
    expect(v.pipeline!.hasArticle, isTrue);
    expect(v.abstract_, 'sažetak');
  });

  group('search.json', () {
    test('tryParse odbija nepoznatu verziju', () {
      expect(SearchCorpus.tryParse({'version': 2, 'episodes': {}}), isNull);
      expect(SearchCorpus.tryParse({'version': 1, 'episodes': []}), isNull);
    });

    test('nadopunjuje listinge učitane prije i poslije korpusa', () {
      final cache = ChannelCache();
      ChannelDetail listing(String id, String vid) => ChannelDetail.fromJson({
            'version': 2,
            'id': id,
            'name': id,
            'videos': [
              {'id': vid, 'title': vid, 'p': 8},
            ],
          });

      cache.seedForTest(listing('prije', 'a'));
      cache.seedSearchCorpusForTest(SearchCorpus.tryParse({
        'version': 1,
        'episodes': {
          'a': {'a': 'sažetak A', 't': ['vjera'], 's': ['Ivan']},
          'b': {'t': ['obitelj']},
        },
      })!);
      cache.seedForTest(listing('poslije', 'b'));

      final a = cache.get('prije')!.videos.single;
      expect(a.abstract_, 'sažetak A');
      expect(a.topics, ['vjera']);
      expect(a.speakers, ['Ivan']);
      expect(cache.get('poslije')!.videos.single.topics, ['obitelj']);
    });

    test('v1 tekst iz listinga se ne prepisuje korpusom', () {
      final v = ChannelVideo.fromJson({
        'id': 'a',
        'title': 'a',
        'abstract': 'iz listinga',
        'topics': ['t1'],
      }).withSearchText(abstract: 'iz korpusa', topics: ['t2']);
      expect(v.abstract_, 'iz listinga');
      expect(v.topics, ['t1']);
    });
  });
}
