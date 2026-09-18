import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/services/cdn_config.dart';
import 'package:podcast_core/services/ebook_service.dart';

/// Ugovor prema CDN-u i prema tuđim aplikacijama u koje datoteka putuje.
/// Imena na CDN-u (`book.epub` / `book.en.epub`) postavlja `upload_to_r2.js` u
/// fetch.domovina.tv — promijeni li se ondje, ovi testovi padnu prvi.
void main() {
  group('CdnConfig ebook URL-ovi', () {
    const id = 'pNSblshqEuU';

    test('hrvatsko i englesko izdanje imaju svoj ključ', () {
      expect(
        CdnConfig.ebookUrl(id),
        'https://cdn.domovina.ai/data/$id/book.epub',
      );
      expect(
        CdnConfig.ebookEnUrl(id),
        'https://cdn.domovina.ai/data/$id/book.en.epub',
      );
    });

    test('probe URL nosi cache-buster, URL za preuzimanje ne', () {
      expect(CdnConfig.ebookProbeUrl(id), contains('?v='));
      expect(CdnConfig.ebookEnProbeUrl(id), contains('?v='));
      expect(CdnConfig.ebookUrl(id), isNot(contains('?')));
      expect(CdnConfig.ebookEnUrl(id), isNot(contains('?')));
    });
  });

  group('EbookService.fileName', () {
    test('transliterira dijakritike i miče interpunkciju', () {
      expect(
        EbookService.fileName(
          title: 'Nedjeljom u 2: Damir Sabol — čišćenje?',
          isEn: false,
        ),
        'Nedjeljom-u-2-Damir-Sabol-ciscenje.epub',
      );
    });

    test('englesko izdanje ima -en sufiks', () {
      expect(
        EbookService.fileName(title: 'Damir Sabol', isEn: true),
        'Damir-Sabol-en.epub',
      );
    });

    test('naslov bez ijednog upotrebljivog znaka ne daje golu ekstenziju', () {
      expect(
        EbookService.fileName(title: '???', isEn: false),
        'domovina-ai-epizoda.epub',
      );
    });

    test('ime je omeđeno i ne završava crticom', () {
      final name = EbookService.fileName(title: 'a' * 200, isEn: true);
      expect(name.length, lessThanOrEqualTo(60 + '-en.epub'.length));
      expect(name, isNot(contains('-.')));
    });
  });

  group('EbookAvailability.preferred', () {
    const hr = EbookEdition(isEn: false, url: 'hr.epub');
    const en = EbookEdition(isEn: true, url: 'en.epub');

    test('bira izdanje jezika koji korisnik čita', () {
      const both = EbookAvailability(hr: hr, en: en);
      expect(both.preferred(wantEn: true), en);
      expect(both.preferred(wantEn: false), hr);
      expect(both.editions, [hr, en]);
    });

    test('kad engleskog izdanja nema, nudi hrvatsko', () {
      // Stvarno stanje 15.9.2026.: `book.epub` postoji, `book.en.epub` još ne —
      // englesko izdanje je u pipeline ušlo tek istog dana.
      const samoHr = EbookAvailability(hr: hr);
      expect(samoHr.preferred(wantEn: true), hr);
      expect(samoHr.editions, [hr]);
      expect(samoHr.any, isTrue);
    });

    test('bez ijednog izdanja nema što ponuditi', () {
      expect(EbookAvailability.none.any, isFalse);
      expect(EbookAvailability.none.preferred(wantEn: false), isNull);
    });
  });

  group('EbookService.formatSize', () {
    test('MB s hrvatskim decimalnim zarezom, kB bez decimale', () {
      expect(EbookService.formatSize(2638696), '2,6 MB');
      expect(EbookService.formatSize(940000), '940 kB');
    });
  });
}
