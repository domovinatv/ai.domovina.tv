import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/services/cdn_config.dart';

/// Izbor WebP varijante thumbnaila. Logika je tiha — ako se pokvari, app i
/// dalje radi (fallback na PNG), samo opet povlači 810 KB po slici umjesto
/// 13 KB. Zato testovi.
void main() {
  group('CdnConfig.thumbnailUrlPattern', () {
    test('hvata YouTube ID iz kanonskog thumbnail URL-a', () {
      final m = CdnConfig.thumbnailUrlPattern
          .firstMatch('https://cdn.domovina.ai/images/KvJlt9ewgTQ/thumbnail.png');
      expect(m, isNotNull);
      expect(m!.group(1), 'KvJlt9ewgTQ');
    });

    test('hvata ID-eve s crticom i podvlakom (validni YouTube znakovi)', () {
      for (final id in ['H-p2Hl6x7I0', '3_jA9b-myNQ', '_-abcDEF123']) {
        final m = CdnConfig.thumbnailUrlPattern
            .firstMatch('https://cdn.domovina.ai/images/$id/thumbnail.png');
        expect(m?.group(1), id, reason: 'ID $id');
      }
    });

    test('NE hvata screenshotove — oni imaju svoj put i nisu konvertirani', () {
      expect(
        CdnConfig.thumbnailUrlPattern.hasMatch(
            'https://cdn.domovina.ai/images/KvJlt9ewgTQ/screenshots/00-15-30.png'),
        isFalse,
      );
    });

    test('NE hvata og-share.jpg — social sharing namjerno ostaje JPEG', () {
      expect(
        CdnConfig.thumbnailUrlPattern.hasMatch(
            'https://cdn.domovina.ai/images/KvJlt9ewgTQ/og-share.jpg'),
        isFalse,
      );
    });

    test('NE hvata channel avatare — nisu per-epizoda thumbnaili', () {
      expect(
        CdnConfig.thumbnailUrlPattern.hasMatch(
            'https://cdn.domovina.ai/channels/images/domovina_tv/avatar_square.jpg'),
        isFalse,
      );
    });

    test('NE hvata URL s cache-busterom (anchored na kraj)', () {
      // Ako se ikad doda `?v=…` na thumbnail, varijanta se NE smije primijeniti
      // naslijepo — cache-buster bi se izgubio.
      expect(
        CdnConfig.thumbnailUrlPattern.hasMatch(
            'https://cdn.domovina.ai/images/KvJlt9ewgTQ/thumbnail.png?v=123'),
        isFalse,
      );
    });
  });

  group('CdnConfig.pickThumbWidth', () {
    test('bira najmanju varijantu koja pokriva traženu širinu', () {
      expect(CdnConfig.pickThumbWidth(100), 320);
      expect(CdnConfig.pickThumbWidth(320), 320);
      expect(CdnConfig.pickThumbWidth(321), 640);
      expect(CdnConfig.pickThumbWidth(640), 640);
      expect(CdnConfig.pickThumbWidth(641), 1280);
      expect(CdnConfig.pickThumbWidth(1280), 1280);
    });

    test('preko najveće varijante vraća najveću, ne baca', () {
      // Vrlo širok layout na DPR 3 — blago skaliranje prema dolje je i dalje
      // neusporedivo bolje od 810 KB PNG-a.
      expect(CdnConfig.pickThumbWidth(4000), 1280);
    });

    test('realni slučajevi: lista/kartica/fullscreen na DPR 2 i 3', () {
      expect(CdnConfig.pickThumbWidth(160 * 2), 320); // lista, DPR 2
      expect(CdnConfig.pickThumbWidth(360 * 2), 1280); // kartica, DPR 2
      expect(CdnConfig.pickThumbWidth(160 * 3), 640); // lista, DPR 3
    });

    test('širine su sortirane uzlazno — pickThumbWidth se oslanja na to', () {
      final sorted = [...CdnConfig.thumbVariantWidths]..sort();
      expect(CdnConfig.thumbVariantWidths, sorted);
    });
  });

  group('CdnConfig.thumbnailVariantUrl', () {
    test('gradi ključ koji odgovara onome što uploader piše na R2', () {
      // Mora se poklapati s getFlutterKey u fetch.domovina.tv/upload_to_r2.js:
      //   {base}.thumb-{w}.webp → images/{videoId}/thumb-{w}.webp
      expect(
        CdnConfig.thumbnailVariantUrl('KvJlt9ewgTQ', 320),
        'https://cdn.domovina.ai/images/KvJlt9ewgTQ/thumb-320.webp',
      );
    });

    test('original i varijanta dijele isti /images/{id}/ prefiks', () {
      const id = 'KvJlt9ewgTQ';
      final original = CdnConfig.thumbnailUrl(id);
      final variant = CdnConfig.thumbnailVariantUrl(id, 640);
      final prefix = '${CdnConfig.base}/images/$id/';
      expect(original, startsWith(prefix));
      expect(variant, startsWith(prefix));
    });

    test('svaka deklarirana širina daje različit URL', () {
      final urls = CdnConfig.thumbVariantWidths
          .map((w) => CdnConfig.thumbnailVariantUrl('KvJlt9ewgTQ', w))
          .toSet();
      expect(urls.length, CdnConfig.thumbVariantWidths.length);
    });
  });
}
