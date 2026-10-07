/// Logika plaćenih sponzorskih trenutaka: mjerenje (impression /
/// play_through / click), sidrenje u članku, teme za izlog, tijelo narudžbe i
/// tipizirane greške checkouta.
library;

import 'dart:convert';

import 'package:domovina_ai/models/sponsor_topic.dart';
import 'package:domovina_ai/models/sponsored_moment.dart';
import 'package:domovina_ai/pinka_sdk/pinka_sdk.dart';
import 'package:domovina_ai/services/sponsored_moments_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

SponsoredMoment _m(int start, int end, {String brand = 'Brand'}) =>
    SponsoredMoment(
      slotKey: 'vid@$start',
      youtubeId: 'vid',
      start: start,
      end: end,
      brand: brand,
      linkUrl: 'https://brand.example',
    );

class _Sink implements SponsoredMomentSink {
  final events = <String>[];
  @override
  void record(SponsoredMomentEvent event, SponsoredMoment moment) =>
      events.add('${event.wire}:${moment.slotKey}');
}

Duration _s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

/// Prirodna reprodukcija: pozicija raste po 0,2 s (stream ~5×/s).
void _play(SponsoredMomentsController c, num from, num to) {
  for (var t = from; t <= to; t += 0.2) {
    c.onPosition(_s(t));
  }
}

void main() {
  setUp(SponsoredMomentsController.resetSessionForTest);

  group('mjerenje', () {
    test('odgledan trenutak: jedna impresija i play_through', () {
      final sink = _Sink();
      final c = SponsoredMomentsController(
        SponsoredMoments([_m(10, 20)]),
        sink: sink,
      );
      _play(c, 5, 22);
      expect(sink.events, ['impression:vid@10', 'play_through:vid@10']);
      expect(c.active.value, isNull);
    });

    test('active prati trenutak dok svira', () {
      final c = SponsoredMomentsController(SponsoredMoments([_m(10, 20)]));
      _play(c, 5, 12);
      expect(c.active.value?.slotKey, 'vid@10');
    });

    test('skok unutar trenutka poništava play_through', () {
      final sink = _Sink();
      final c = SponsoredMomentsController(
        SponsoredMoments([_m(10, 40)]),
        sink: sink,
      );
      _play(c, 5, 15);
      c.onPosition(_s(30)); // korisnik je preskočio dio oglasa
      _play(c, 30, 42);
      expect(sink.events, ['impression:vid@10']);
    });

    test('ulazak skokom („Poslušaj") je impresija, ali ne play_through', () {
      final sink = _Sink();
      final c = SponsoredMomentsController(
        SponsoredMoments([_m(100, 110)]),
        sink: sink,
      );
      _play(c, 0, 3);
      c.onPosition(_s(100));
      _play(c, 100, 112);
      expect(sink.events, ['impression:vid@100']);
    });

    test('izlazak skokom van trenutka nije play_through', () {
      final sink = _Sink();
      final c = SponsoredMomentsController(
        SponsoredMoments([_m(10, 20)]),
        sink: sink,
      );
      _play(c, 5, 15);
      c.onPosition(_s(300));
      expect(sink.events, ['impression:vid@10']);
    });

    test('impresija jednom po sesiji, i kroz novi kontroler', () {
      final sink = _Sink();
      final moments = SponsoredMoments([_m(10, 20)]);
      final a = SponsoredMomentsController(moments, sink: sink);
      _play(a, 5, 12);
      _play(a, 5, 12); // natrag pa opet kroz trenutak
      final b = SponsoredMomentsController(moments, sink: sink);
      _play(b, 5, 12); // isti trenutak na ponovno otvorenoj epizodi
      expect(
        sink.events.where((e) => e.startsWith('impression')),
        ['impression:vid@10'],
      );
    });

    test('brzina 2,0× nije skok (korak 0,4 s < prag)', () {
      final sink = _Sink();
      final c = SponsoredMomentsController(
        SponsoredMoments([_m(10, 20)]),
        sink: sink,
      );
      for (var t = 8.0; t <= 22; t += 0.4) {
        c.onPosition(_s(t));
      }
      expect(sink.events, ['impression:vid@10', 'play_through:vid@10']);
    });

    test('dva uzastopna trenutka: prvi završi, drugi počne', () {
      final sink = _Sink();
      final c = SponsoredMomentsController(
        SponsoredMoments([_m(10, 20, brand: 'A'), _m(20, 30, brand: 'B')]),
        sink: sink,
      );
      _play(c, 9, 31);
      expect(sink.events, [
        'impression:vid@10',
        'play_through:vid@10',
        'impression:vid@20',
        'play_through:vid@20',
      ]);
    });

    test('istek zakupa usred slušanja gasi oznaku i mjerenje', () {
      final sink = _Sink();
      var now = DateTime.utc(2026, 11, 5, 23, 59);
      final m = SponsoredMoment(
        slotKey: 'vid@10',
        youtubeId: 'vid',
        start: 10,
        end: 100,
        brand: 'B',
        liveUntil: DateTime.utc(2026, 11, 6),
      );
      final c = SponsoredMomentsController(
        SponsoredMoments([m]),
        sink: sink,
        clock: () => now,
      );
      _play(c, 9, 20);
      expect(c.active.value, m);
      now = DateTime.utc(2026, 11, 6, 0, 1);
      _play(c, 20, 40);
      expect(c.active.value, isNull);
      expect(c.moments.isEmpty, isTrue);
      expect(sink.events, ['impression:vid@10']);
    });

    test('rasponi za seek bar su ista lista (painter uspoređuje identitet)', () {
      final m = SponsoredMoments([_m(10, 20)]);
      expect(identical(m.ranges, m.ranges), isTrue);
    });

    test('click ide u sink', () {
      final sink = _Sink();
      final m = _m(10, 20);
      SponsoredMomentsController(
        SponsoredMoments([m]),
        sink: sink,
      ).recordClick(m);
      expect(sink.events, ['click:vid@10']);
    });

    test('prag ispod 1 s nije dopušten', () {
      expect(
        () => SponsoredMomentsController(
          SponsoredMoments.empty,
          jumpThreshold: const Duration(milliseconds: 500),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('model', () {
    test('red bez branda ili s lošim rasponom se preskače', () {
      final m = SponsoredMoments.fromRows([
        {'youtube_id': 'v', 'start_sec': 10, 'end_sec': 20, 'brand': ' '},
        {'youtube_id': 'v', 'start_sec': 20, 'end_sec': 20, 'brand': 'X'},
        {'youtube_id': 'v', 'start_sec': 30, 'end_sec': 40, 'brand': 'Ok'},
      ]);
      expect(m.moments.map((m) => m.brand), ['Ok']);
    });

    test('poveznica koja nije https se odbacuje', () {
      SponsoredMoment parse(String url) => SponsoredMoment.tryParse({
        'youtube_id': 'v',
        'start_sec': 1,
        'end_sec': 2,
        'brand': 'B',
        'link_url': url,
      })!;
      expect(parse('http://x.hr').linkUrl, isNull);
      expect(parse('javascript:alert(1)').linkUrl, isNull);
      expect(parse('https://x.hr/a').linkUrl, 'https://x.hr/a');
    });

    test('oznaka u članku ide u sekciju u koju pada POČETAK', () {
      final marks = SponsoredMoments([
        _m(5, 50),
        _m(130, 200),
        _m(300, 400),
      ]).marksBySection([
        (ts: 'a', seconds: 30),
        (ts: 'b', seconds: 120),
        (ts: 'c', seconds: 300),
      ]);
      expect(marks['a']!.map((m) => m.start), [5]); // prije prve → prva
      expect(marks['b']!.map((m) => m.start), [130]);
      expect(marks['c']!.map((m) => m.start), [300]); // točno na granici
    });
  });

  group('teme za izlog (stvarne teme kanala domovina_tv, 7.10.2026.)', () {
    Set<SponsorTopic> c(List<String> t) => SponsorTopic.classify(topics: t);

    test('vjera', () {
      expect(
        c(['katolički susreti za samce', 'organizacija događaja']),
        contains(SponsorTopic.faith),
      );
      expect(c(['etično bankarstvo', 'franjina ekonomija']), {
        SponsorTopic.faith,
        SponsorTopic.business,
      });
    });

    test('politika', () {
      expect(
        c(["izborni sustav i d'hondtova metoda", 'financiranje političkih stranaka']),
        contains(SponsorTopic.politics),
      );
      expect(
        c(['demokracija i izbori', 'start-up ekosustav']),
        {SponsorTopic.politics, SponsorTopic.business},
      );
    });

    test('posao i tehnologija bez vjere i politike', () {
      expect(c(['ai u programiranju', 'flutter aplikacije']), {
        SponsorTopic.business,
      });
    });

    test('nijedna tema ne znači prazan skup, ne pogađanje', () {
      expect(c(['kulinarstvo', 'putovanja']), isEmpty);
    });
  });

  group('narudžba (ugovor §5)', () {
    test('tijelo: trim, VAT velikim slovima, bez praznih polja', () {
      final json = const PinkaSponsorOrder(
        brand: ' Primjer ',
        tagline: '',
        linkUrl: 'https://primjer.hr',
        termsAccepted: true,
        buyer: PinkaSponsorBuyer(
          company: 'Primjer d.o.o.',
          email: ' racuni@primjer.hr ',
          oib: '',
          vatId: 'hr 69435151530',
          city: 'Zagreb',
          country: 'hr',
        ),
      ).toJson();
      expect(json, {
        'brand': 'Primjer',
        'link_url': 'https://primjer.hr',
        'terms_accepted': true,
        'buyer': {
          'company': 'Primjer d.o.o.',
          'vat_id': 'HR69435151530',
          'email': 'racuni@primjer.hr',
          'address': {'city': 'Zagreb', 'country': 'HR'},
        },
      });
    });

    test('OIB kontrolna znamenka (ISO 7064 MOD 11,10)', () {
      expect(isValidOib('69435151530'), isTrue);
      expect(isValidOib('12345678903'), isTrue);
      expect(isValidOib('69435151531'), isFalse);
      expect(isValidOib('1234567890'), isFalse);
      expect(isValidOib('1234567890a'), isFalse);
    });
  });

  group('greške checkouta (FunctionException, ne res.data)', () {
    PinkaClient client(int status, Map<String, Object?> body) {
      final c = MockClient((req) async {
        if (!req.url.path.endsWith('/functions/v1/pinka-contribute')) {
          return http.Response('', 404);
        }
        return http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      });
      final supa = sb.SupabaseClient(
        'http://localhost',
        'anon',
        httpClient: c,
        authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      );
      return _SessionlessClient(supa);
    }

    const order = PinkaSponsorOrder(
      brand: 'B',
      termsAccepted: true,
      buyer: PinkaSponsorBuyer(company: 'C', email: 'c@c.hr'),
    );

    test('409 slot_taken → PinkaSlotTaken s ključem', () async {
      final c = client(409, {'error': 'slot_taken:WRE248YCIeI@33'});
      await expectLater(
        c.contributeSponsor(
          campaignId: 'x',
          slotKeys: const ['WRE248YCIeI@33'],
          order: order,
        ),
        throwsA(
          isA<PinkaSlotTaken>().having(
            (e) => e.slotKey,
            'slotKey',
            'WRE248YCIeI@33',
          ),
        ),
      );
    });

    test('409 too_many_holds → PinkaSponsorRejected', () async {
      final c = client(409, {'error': 'too_many_holds'});
      await expectLater(
        c.contributeSponsor(campaignId: 'x', slotKeys: const ['a'], order: order),
        throwsA(
          isA<PinkaSponsorRejected>()
              .having((e) => e.code, 'code', 'too_many_holds')
              .having((e) => e.status, 'status', 409),
        ),
      );
    });

    test('400 invalid_sponsor:buyer_oib → kod i polje odvojeni', () async {
      final c = client(400, {'error': 'invalid_sponsor:buyer_oib'});
      await expectLater(
        c.contributeSponsor(campaignId: 'x', slotKeys: const ['a'], order: order),
        throwsA(
          isA<PinkaSponsorRejected>()
              .having((e) => e.code, 'code', 'invalid_sponsor')
              .having((e) => e.detail, 'detail', 'buyer_oib'),
        ),
      );
    });

    test('tijelo greške kao String (bez JSON content-typea) se parsira', () async {
      final c = MockClient(
        (req) async => http.Response(
          '{"error":"too_many_holds"}',
          409,
          headers: {'content-type': 'text/plain'},
        ),
      );
      final pc = _SessionlessClient(
        sb.SupabaseClient(
          'http://localhost',
          'anon',
          httpClient: c,
          authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
        ),
      );
      await expectLater(
        pc.contributeSponsor(campaignId: 'x', slotKeys: const ['a'], order: order),
        throwsA(
          isA<PinkaSponsorRejected>().having((e) => e.code, 'code', 'too_many_holds'),
        ),
      );
    });

    test('donacijski contribute: 409 je sada PinkaSlotTaken', () async {
      final c = client(409, {'error': 'slot_taken:grid@1'});
      await expectLater(
        c.contribute(campaignId: 'x', amountCents: 500, slotKeys: const ['g']),
        throwsA(isA<PinkaSlotTaken>()),
      );
    });
  });
}

/// Test ne treba GoTrue: preskače anonimnu prijavu.
class _SessionlessClient extends PinkaClient {
  _SessionlessClient(sb.SupabaseClient client) : super(client: client);

  @override
  Future<void> ensureSession() async {}
}
