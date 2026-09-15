import 'package:flutter_test/flutter_test.dart';
import 'package:domovina_ai/services/episode_language.dart';
import 'package:domovina_ai/services/share_links.dart';

/// Ugovor share poveznica.
///
/// Povod (15.9.2026.): „Kopiraj poveznicu" na poglavlju uvijek je davao
/// hrvatski URL, i kad je korisnik čitao engleski. Na webu se to nije vidjelo
/// jer se link dalo prepisati iz adresne trake (koju `url_sync` održava); u
/// iOS/Android aplikaciji adresne trake nema, pa je gubitak bio potpun.
///
/// Segmenti moraju biti `/v/<id>/t/<sec>/en`, istim redom koji matcha
/// `web/_worker.js` i koji piše `url_sync` — test je ovdje da ta tri mjesta ne
/// odu jedno od drugoga.
void main() {
  group('episodeShareUrl', () {
    test('base URL bez trenutka i na hrvatskom', () {
      expect(
        episodeShareUrl('abc123'),
        'https://domovina.ai/v/abc123',
      );
    });

    test('trenutak daje /t/<sec>', () {
      expect(
        episodeShareUrl('abc123', seconds: 1185),
        'https://domovina.ai/v/abc123/t/1185',
      );
    });

    test('engleski daje /en NA KRAJU, iza /t/', () {
      expect(
        episodeShareUrl('abc123', seconds: 1185, lang: EpisodeLanguage.en),
        'https://domovina.ai/v/abc123/t/1185/en',
      );
    });

    test('engleski bez trenutka', () {
      expect(
        episodeShareUrl('abc123', lang: EpisodeLanguage.en),
        'https://domovina.ai/v/abc123/en',
      );
    });

    test('prvih par sekundi NIJE trenutak — /t/0 bi bio zaseban cache unos '
        'crawlera za isti sadržaj', () {
      expect(episodeShareUrl('abc123', seconds: 0),
          'https://domovina.ai/v/abc123');
      expect(episodeShareUrl('abc123', seconds: 5),
          'https://domovina.ai/v/abc123');
      expect(episodeShareUrl('abc123', seconds: 6),
          'https://domovina.ai/v/abc123/t/6');
      expect(episodeShareUrl('abc123', seconds: null),
          'https://domovina.ai/v/abc123');
    });

    test('oznaka govornika ide kao query, iza jezičnog segmenta', () {
      expect(
        episodeShareUrl(
          'abc123',
          seconds: 600,
          lang: EpisodeLanguage.en,
          personSlug: 'don-damir-stojic',
        ),
        'https://domovina.ai/v/abc123/t/600/en?p=don-damir-stojic',
      );
    });

    test('slug se enkodira — sirov slug bi mogao razbiti query', () {
      expect(
        episodeShareUrl('abc123', personSlug: 'ime prezime&x=1'),
        'https://domovina.ai/v/abc123?p=ime%20prezime%26x%3D1',
      );
    });

    test('prazan slug se ne dopisuje', () {
      expect(episodeShareUrl('abc123', personSlug: ''),
          'https://domovina.ai/v/abc123');
    });

    test('URL je apsolutan — kopira se u tuđe aplikacije', () {
      final u = Uri.parse(episodeShareUrl('abc123', seconds: 42));
      expect(u.hasScheme, isTrue);
      expect(u.scheme, 'https');
      expect(u.host, 'domovina.ai');
    });
  });
}
