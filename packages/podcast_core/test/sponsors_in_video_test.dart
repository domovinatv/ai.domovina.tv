import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/models/sponsors_in_video.dart';
import 'package:podcast_core/services/data_service.dart';
import 'package:podcast_core/theme/app_theme.dart';
import 'package:podcast_core/widgets/sponsors_in_video_section.dart';

/// Ugovor `sponsors_in_video.json` (schema_version 1) — producent je
/// `fetch.domovina.tv/detect_sponsors.js`, ugovor u
/// `fetch.domovina.tv/docs/2026-09-23-sponzori-u-snimci.md`.
///
/// Fixture je skraćena kopija stvarnih odgovora s CDN-a (23.9.2026.):
/// `aue1GuuMsbA` (spot e-Duhovnih vježbi 5963–6008, Cafe Brazil mention,
/// jedan `_unattributed`) i `B8xUC-nIVkM` (Plazma rubrika + wardrobe).
const _iva = '''
{
  "type": "sponsors_in_video", "schema_version": 1,
  "generator": "detect_sponsors.js@1", "video_id": "aue1GuuMsbA",
  "has_transcript": true,
  "sponsors": [
    {"id": "cafe-brazil", "name": "Cafe Brazil", "role": "partner",
     "url": "https://eurovip-brazil-kava.com/",
     "instagram": "https://www.instagram.com/cafebrazil.ba",
     "blurb": null, "description_lines": [], "source": "description",
     "segments": [
       {"kind": "mention", "start": 3468, "end": 3483, "duration": 15,
        "start_hms": "00:57:48", "end_hms": "00:58:03", "playable": false,
        "confidence": "medium", "signals": [], "text": "Hvala Brazil kavi"}
     ]},
    {"id": "e-duhovne-vjezbe", "name": "e-Duhovne vježbe", "role": "sponsor",
     "url": "https://eduhovnevjezbe.hr/", "instagram": null, "blurb": null,
     "source": "description",
     "segments": [
       {"kind": "mention", "start": 6007, "end": 6028, "playable": false},
       {"kind": "spot", "start": 5963, "end": 6008, "duration": 45,
        "start_hms": "01:39:23", "end_hms": "01:40:08", "playable": true,
        "confidence": "high"}
     ]},
    {"id": "_unattributed", "name": null, "role": "sponsor", "url": null,
     "instagram": null, "blurb": null, "source": "transcript",
     "segments": [
       {"kind": "host_read", "start": 3402, "end": 3420, "playable": false}
     ]}
  ]
}
''';

const _rastuci = '''
{
  "type": "sponsors_in_video", "schema_version": 1, "video_id": "B8xUC-nIVkM",
  "sponsors": [
    {"id": "unique-concept-store", "name": "Unique Concept Store",
     "role": "wardrobe", "url": null,
     "instagram": "https://www.instagram.com/unique_concept_store_/",
     "blurb": null, "segments": []},
    {"id": "plazma", "name": "Plazma", "role": "sponsor",
     "url": "https://www.plazma.rs/", "instagram": null,
     "blurb": "Jedinstven ukus, neodoljiv miris, kvalitet i vrhunski sastojci su ono zbog čega Plazma zauzima važno mjesto u našim srcima i čini je životnim suputnikom. Sa Plazmom su odrastale i odrastaju brojne generacije, jer ona inspirira i tu je da upotpuni naše dragocjene trenutke. Za bezbrižne dane djetinjstva i odrastanje u kojem osjećaš punu podršku!",
     "segments": [
       {"kind": "host_read", "start": 151, "end": 164, "playable": true},
       {"kind": "rubric", "start": 3601, "end": 3830, "playable": true}
     ]}
  ]
}
''';

SponsorsInVideo _parse(String raw) =>
    SponsorsInVideo.fromJson(jsonDecode(raw) as Map<String, dynamic>);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('hr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUp(() => AppBrand.init(domovinaBrand));

  group('parsiranje', () {
    test('stvarna Ivina epizoda: spot je playable, raspon 5963–6008', () {
      final d = _parse(_iva);
      expect(d.schemaVersion, 1);
      expect(d.videoId, 'aue1GuuMsbA');
      expect(d.sponsors, hasLength(3));

      final eduh = d.sponsors.firstWhere((s) => s.id == 'e-duhovne-vjezbe');
      expect(eduh.role, SponsorInVideoRole.sponsor);
      // Segmenti su poredani po početku bez obzira na redoslijed u datoteci.
      expect(eduh.segments.map((s) => s.start), [5963, 6007]);
      final spot = eduh.playableSegments.single;
      expect(spot.kind, SponsorInVideoKind.spot);
      expect((spot.start, spot.end), (5963, 6008));
      expect(spot.confidence, 'high');
    });

    test('_unattributed i zapis bez imena se ne prikazuju', () {
      final d = _parse(_iva);
      expect(d.named.map((s) => s.id), ['cafe-brazil', 'e-duhovne-vjezbe']);
      expect(d.hasNamed, isTrue);

      final onlyUnnamed = SponsorsInVideo.fromJson({
        'sponsors': [
          {'id': '_unattributed', 'name': null, 'segments': []},
          {'id': 'x', 'name': '   ', 'segments': []},
        ],
      });
      expect(onlyUnnamed.hasNamed, isFalse);
    });

    test('prazan niz znači „nema sponzora", ne grešku', () {
      final d = _parse(
        '{"type":"sponsors_in_video","schema_version":1,'
        '"video_id":"AAzm0ftoqsg","sponsors":[],"has_transcript":true}',
      );
      expect(d.sponsors, isEmpty);
      expect(d.hasNamed, isFalse);
      expect(d.playableRanges, isEmpty);
    });

    test('null polja (name/url/instagram/blurb) ne ruše parser', () {
      final d = SponsorsInVideo.fromJson({
        'sponsors': [
          {
            'id': 'a',
            'name': 'A',
            'role': null,
            'url': null,
            'instagram': null,
            'blurb': null,
            'segments': null,
          },
        ],
      });
      final a = d.sponsors.single;
      expect(a.url, isNull);
      expect(a.instagram, isNull);
      expect(a.blurb, isNull);
      expect(a.segments, isEmpty);
      expect(a.role, SponsorInVideoRole.other);
    });

    test('nepoznat kind postaje unknown i NIKAD nije playable', () {
      final d = SponsorsInVideo.fromJson({
        'sponsors': [
          {
            'id': 'a',
            'name': 'A',
            'role': 'sponsor',
            'segments': [
              {'kind': 'jingle', 'start': 10, 'end': 40, 'playable': true},
            ],
          },
        ],
      });
      final seg = d.sponsors.single.segments.single;
      expect(seg.kind, SponsorInVideoKind.unknown);
      expect(seg.playable, isFalse);
    });

    test('nepoznata uloga postaje other; wardrobe/studio su krediti', () {
      expect(SponsorInVideoRole.parse('mecena'), SponsorInVideoRole.other);
      expect(SponsorInVideoRole.wardrobe.isCredit, isTrue);
      expect(SponsorInVideoRole.studio.isCredit, isTrue);
      expect(SponsorInVideoRole.partner.isCredit, isFalse);
    });

    test('noviji schema_version se pokuša pročitati', () {
      final d = SponsorsInVideo.fromJson({
        'schema_version': 2,
        'new_top_level': {'x': 1},
        'sponsors': [
          {
            'id': 'a',
            'name': 'A',
            'role': 'sponsor',
            'extra': [1, 2],
            'segments': [
              {'kind': 'spot', 'start': 5, 'end': 50.6, 'playable': true},
            ],
          },
        ],
      });
      expect(d.schemaVersion, 2);
      expect(d.sponsors.single.playableSegments.single.end, 51);
    });

    test('pokvaren zapis se preskače, ostali prežive', () {
      final d = SponsorsInVideo.fromJson({
        'sponsors': [
          'nije objekt',
          {
            'id': 'a',
            'name': 'A',
            'segments': [
              {'kind': 'spot', 'start': 'x', 'playable': true},
              {'kind': 'spot', 'start': 10, 'end': 5, 'playable': true},
            ],
          },
        ],
      });
      final a = d.sponsors.single;
      // Segment bez broja za početak ispada; obrnuti raspon se svodi na nulu
      // i gubi `playable` (nema što pustiti).
      expect(a.segments.single.start, 10);
      expect(a.segments.single.playable, isFalse);
    });

    test('vanjska poveznica mora biti http(s)', () {
      final d = SponsorsInVideo.fromJson({
        'sponsors': [
          {
            'id': 'a',
            'name': 'A',
            'url': 'javascript:alert(1)',
            'instagram': 'instagram.com/bez-sheme',
          },
        ],
      });
      expect(d.sponsors.single.url, isNull);
      expect(d.sponsors.single.instagram, isNull);
    });

    test('isti segment pripisan dvama sponzorima → jedna oznaka na crti', () {
      final d = SponsorsInVideo.fromJson({
        'sponsors': [
          for (final id in ['hipp', 'plazma'])
            {
              'id': id,
              'name': id,
              'role': 'sponsor',
              'segments': [
                {
                  'kind': 'host_read',
                  'start': 86,
                  'end': 137,
                  'playable': true,
                },
              ],
            },
        ],
      });
      expect(d.playableRanges, hasLength(1));
      expect(d.playableRanges.single.start, const Duration(seconds: 86));
    });
  });

  group('DataService.loadSponsorsInVideo', () {
    const svc = DataService(youtubeId: 'abc123');

    test('404 (i nakon retryja) → null, bez petlje', () async {
      final log = <String>[];
      await http.runWithClient(
        () async {
          expect(await svc.loadSponsorsInVideo(), isNull);
        },
        () => MockClient((req) async {
          log.add(req.url.toString());
          return http.Response('Not Found', 404);
        }),
      );
      expect(log, hasLength(2), reason: 'goli URL + jedan cache-buster');
      expect(log.first, endsWith('/data/abc123/sponsors_in_video.json'));
    });

    test('nečitljiv JSON ili mreža → null, nikad iznimka', () async {
      await http.runWithClient(() async {
        expect(await svc.loadSponsorsInVideo(), isNull);
      }, () => MockClient((_) async => http.Response('<html>', 200)));
      await http.runWithClient(() async {
        expect(await svc.loadSponsorsInVideo(), isNull);
      }, () => MockClient((_) async => throw http.ClientException('offline')));
    });

    test('200 → parsiran model', () async {
      await http.runWithClient(
        () async {
          final d = await svc.loadSponsorsInVideo();
          expect(d?.named.map((s) => s.name), [
            'Cafe Brazil',
            'e-Duhovne vježbe',
          ]);
        },
        () => MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(_iva),
            200,
            // CDN šalje charset (provjereno curlom 23.9.2026.); bez njega bi
            // `package:http` tijelo čitao kao latin1.
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
    });
  });

  group('SponsorsInVideoSection', () {
    testWidgets('bez imenovanog sponzora ne zauzima ništa', (tester) async {
      await tester.pumpWidget(
        _host(
          SponsorsInVideoSection(
            data: SponsorsInVideo.fromJson({
              'sponsors': [
                {'id': '_unattributed', 'name': null},
              ],
            }),
          ),
        ),
      );
      expect(tester.getSize(find.byType(SponsorsInVideoSection)), Size.zero);

      await tester.pumpWidget(_host(const SponsorsInVideoSection(data: null)));
      expect(tester.getSize(find.byType(SponsorsInVideoSection)), Size.zero);
    });

    testWidgets('Ivin spot: „Poslušaj" preda točan raspon; zahvala je skok', (
      tester,
    ) async {
      SponsorInVideoSegment? listened;
      SponsorInVideoSegment? jumped;
      await tester.pumpWidget(
        _host(
          SponsorsInVideoSection(
            data: _parse(_iva),
            onListen: (s) => listened = s,
            onJump: (s) => jumped = s,
          ),
        ),
      );

      expect(find.text('Uz podršku'), findsOneWidget);
      expect(find.text('Sponzor epizode'), findsOneWidget);
      expect(find.text('Partner podcasta'), findsOneWidget);
      // `_unattributed` se ne prikazuje ni kao kartica ni kao gumb.
      expect(find.textContaining('3402'), findsNothing);

      await tester.tap(find.textContaining('Poslušaj poruku sponzora'));
      expect((listened!.start, listened!.end), (5963, 6008));

      await tester.tap(find.text('Zahvala na 57:48'));
      expect(jumped!.start, 3468);
    });

    testWidgets('rubrika ima svoj gumb, garderoba je samo kredit', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(SponsorsInVideoSection(data: _parse(_rastuci), onListen: (_) {})),
      );
      expect(
        find.textContaining('Poslušaj sponzoriranu rubriku'),
        findsOneWidget,
      );
      expect(find.textContaining('Poslušaj poruku sponzora'), findsOneWidget);
      expect(find.text('Garderoba: '), findsOneWidget);
      expect(find.text('Unique Concept Store'), findsOneWidget);
      expect(find.text('plazma.rs'), findsOneWidget);
      // Dugačak opis je skraćen i nudi „više".
      expect(find.text('više'), findsOneWidget);
      await tester.tap(find.text('više'));
      await tester.pump();
      expect(find.text('manje'), findsOneWidget);
    });

    testWidgets('dok player nije spreman gumbi su onemogućeni', (tester) async {
      await tester.pumpWidget(
        _host(SponsorsInVideoSection(data: _parse(_iva))),
      );
      final btn = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.textContaining('Poslušaj poruku sponzora'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(btn.onPressed, isNull);
    });
  });

  group('SponsorsInVideoPlayerStrip', () {
    testWidgets('svaki sponzor ima svoj redak i svoj gumb', (tester) async {
      // Prijava 24.9.2026.: „Uz podršku: Cafe Brazil" + gumb „e-Duhovne
      // vježbe · 0:45" ispod čitalo se kao da je aplikacija Cafe Brazilova.
      SponsorInVideoSegment? listened;
      await tester.pumpWidget(
        _host(
          SponsorsInVideoPlayerStrip(
            data: _parse(_iva),
            onListen: (s) => listened = s,
          ),
        ),
      );
      expect(find.text('Uz podršku'), findsOneWidget);
      expect(find.textContaining('Uz podršku:'), findsNothing);
      expect(
        find.text('Cafe Brazil · Partner podcasta', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('e-Duhovne vježbe · Sponzor epizode', findRichText: true),
        findsOneWidget,
      );
      // Gumb nosi glagol i trajanje; ime je u retku iznad njega.
      expect(find.text('Poslušaj · 0:45'), findsOneWidget);
      await tester.tap(find.text('Poslušaj · 0:45'));
      expect((listened!.start, listened!.end), (5963, 6008));
    });

    testWidgets('rubrika ima svoju oznaku; krediti ne ulaze', (tester) async {
      await tester.pumpWidget(
        _host(SponsorsInVideoPlayerStrip(data: _parse(_rastuci))),
      );
      expect(find.text('Poslušaj · 0:13'), findsOneWidget);
      expect(find.text('Rubrika · 3:49'), findsOneWidget);
      expect(find.textContaining('Unique'), findsNothing);
    });

    testWidgets('bez imenovanog partnera ne zauzima ništa', (tester) async {
      await tester.pumpWidget(
        _host(
          SponsorsInVideoPlayerStrip(
            data: SponsorsInVideo.fromJson({
              'sponsors': [
                {'id': 'x', 'name': 'Studio X', 'role': 'studio'},
                {'id': '_unattributed', 'name': null},
              ],
            }),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(SponsorsInVideoPlayerStrip)),
        Size.zero,
      );
    });
  });

  group('oznake u članku', () {
    const ivaSections = [
      (ts: '00:00:27', seconds: 27),
      (ts: '01:21:46', seconds: 4906),
      (ts: '01:43:05', seconds: 6185),
    ];

    test('sidro je vrijeme: spot 5963 ide u sekciju koja ga sadrži', () {
      // Članak opisuje oglas tek u sekciji od 1:43:05, ali spot počinje na
      // 1:39:23 — oznaka ide tamo gdje je zvuk, ne gdje je tekst.
      final marks = _parse(_iva).marksBySection(ivaSections);
      expect(marks.keys, ['01:21:46']);
      final m = marks['01:21:46']!.single;
      expect(m.sponsors.single.name, 'e-Duhovne vježbe');
      expect(m.segment.start, 5963);
    });

    test('raspon prije prve sekcije ide u prvu; krediti i mention ne', () {
      final marks = _parse(_rastuci).marksBySection([
        (ts: '00:05:00', seconds: 300),
        (ts: '01:00:00', seconds: 3600),
      ]);
      expect(marks['00:05:00']!.single.segment.start, 151);
      expect(marks['01:00:00']!.single.segment.kind, SponsorInVideoKind.rubric);
      expect(_parse(_iva).marksBySection(const []), isEmpty);
    });

    test('isti raspon dvaju sponzora je jedna oznaka s oba imena', () {
      final d = SponsorsInVideo.fromJson({
        'sponsors': [
          for (final n in ['HiPP', 'Plazma'])
            {
              'id': n,
              'name': n,
              'role': 'sponsor',
              'segments': [
                {
                  'kind': 'host_read',
                  'start': 86,
                  'end': 137,
                  'playable': true,
                },
              ],
            },
        ],
      });
      final m = d.marksBySection(const [(ts: '00:00:00', seconds: 0)]);
      expect(m['00:00:00']!.single.sponsors.map((s) => s.name), [
        'HiPP',
        'Plazma',
      ]);
    });

    testWidgets('oznaka imenuje sponzora i vrijeme, gumb pušta raspon', (
      tester,
    ) async {
      SponsorInVideoSegment? listened;
      final marks = _parse(_iva).marksBySection(ivaSections)['01:21:46']!;
      await tester.pumpWidget(
        _host(
          SponsorsInVideoSectionMark(
            marks: marks,
            onListen: (s) => listened = s,
          ),
        ),
      );
      expect(find.text('Poruka sponzora na 1:39:23'), findsOneWidget);
      await tester.tap(find.text('e-Duhovne vježbe · 0:45'));
      expect(listened!.end, 6008);
    });
  });
}
