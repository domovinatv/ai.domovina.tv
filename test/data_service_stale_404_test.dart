import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:domovina_ai/services/data_service.dart';

/// Ugovor: **404 na per-epizoda datoteci nije dokaz da je datoteke nema.**
///
/// Cloudflare cachira 404 od prije nego ih je pipeline uploadao, i to u
/// zasebnom `Vary: Origin` zapisu. Preglednik šalje `Origin` na svaki
/// cross-origin fetch, `dart:io` klijent ne šalje — pa isti URL istoj epizodi
/// vrati 404 na webu i 200 u nativnoj aplikaciji. Izmjereno 19.9.2026. na
/// `aue1GuuMsbA` i `70uXR4DDZiE`: epizoda je na webu prikazivala
/// `EpisodeStage.queued` („epizoda još nije preuzeta") uz YouTube embed, a u
/// iOS aplikaciji se uredno reproducirala.
///
/// `DataService._get` zato na 404 ponovi zahtjev s cache-busterom — to je druga
/// cache adresa, pa ide na origin.
void main() {
  const svc = DataService(youtubeId: 'abc123');

  /// Klijent koji goli URL (bez `?v=`) uvijek odbija 404-om, a cache-bustanu
  /// varijantu poslužuje — točna simulacija otrovanog CF zapisa.
  MockClient poisonedCdn(List<String> log, {String body = '{}'}) =>
      MockClient((req) async {
        log.add(req.url.toString());
        if (req.url.queryParameters.containsKey('v')) {
          return http.Response(body, 200);
        }
        return http.Response('<!doctype html>Not Found', 404);
      });

  /// Klijent koji 404-a bez obzira na cache-buster — datoteke doista nema.
  MockClient emptyCdn(List<String> log) => MockClient((req) async {
        log.add(req.url.toString());
        return http.Response('<!doctype html>Not Found', 404);
      });

  test('otrovani 404 na info.json NE ruši epizodu u fazu queued', () async {
    final log = <String>[];
    await http.runWithClient(() async {
      final info = await svc.loadInfo();
      expect(info.id, '');
    }, () => poisonedCdn(log));

    expect(log.length, 2, reason: 'goli URL pa retry s cache-busterom');
    expect(log[0], endsWith('/data/abc123/info.json'));
    expect(log[1], contains('/data/abc123/info.json?v='));
  });

  test('pošten 404 i dalje baca VideoNotFoundException', () async {
    final log = <String>[];
    await http.runWithClient(() async {
      await expectLater(
        svc.loadInfo(),
        throwsA(isA<VideoNotFoundException>()),
      );
    }, () => emptyCdn(log));

    expect(log.length, 2, reason: 'retry se pokuša točno jednom');
  });

  test('uspješan dohvat iz prve ne šalje dodatni zahtjev', () async {
    final log = <String>[];
    await http.runWithClient(() async {
      await svc.loadInfo();
    }, () => MockClient((req) async {
          log.add(req.url.toString());
          return http.Response('{}', 200);
        }));

    expect(log.length, 1, reason: 'bez 404 nema drugog pokušaja');
    expect(log.single, isNot(contains('?v=')));
  });

  test('otrovani 404 ne smije sakriti ni opcionalne assete', () async {
    for (final probe in <(String, Future<Object?> Function())>[
      ('article.json', svc.loadArticle),
      ('summary.json', svc.loadSummary),
      ('outline.json', svc.loadOutline),
      ('article.en.json', svc.loadArticleEn),
      ('summary.en.json', svc.loadSummaryEn),
      ('article.magisterium.json', svc.loadMagisterium),
    ]) {
      final log = <String>[];
      await http.runWithClient(() async {
        expect(await probe.$2(), isNotNull, reason: probe.$1);
      }, () => poisonedCdn(log));

      expect(log.length, 2, reason: probe.$1);
      expect(log[1], contains('${probe.$1}?v='), reason: probe.$1);
    }
  });

  test('diarized.srt (ne-JSON putanja kroz _fetch) jednako se liječi', () async {
    final log = <String>[];
    await http.runWithClient(() async {
      final t = await svc.loadSpeakerTimeline();
      expect(t, isNotNull);
    }, () => poisonedCdn(
          log,
          body: '1\n00:00:01,000 --> 00:00:02,000\n[SPEAKER_00] Dobar dan\n',
        ));

    expect(log.length, 2);
    expect(log[1], contains('/data/abc123/diarized.srt?v='));
  });

  test('channel listing zadržava svoj cache-buster i ne retrya', () async {
    final log = <String>[];
    await http.runWithClient(() async {
      await ChannelService.loadChannel('iva_kraljevic');
    }, () => MockClient((req) async {
          log.add(req.url.toString());
          return http.Response('{"videos":[]}', 200);
        }));

    expect(log.length, 1);
    expect(log.single, contains('/channels/data/iva_kraljevic.json?v='));
  });
}
