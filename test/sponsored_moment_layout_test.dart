/// Širinski budžet trake „Sponzorirano · {brand}" u playeru.
///
/// Traka živi u najužim stupcima aplikacije: `VideoPanel` (360 dp) i
/// `_PlayerTab` jednostavnog prikaza na najužem telefonu (320 dp). Ugovor
/// dopušta brand do 60 i rečenicu do 120 znakova, pa se ovdje crta najgori
/// slučaj: najdulji brand, najdulja rečenica, dugačak host poveznice i aktivno
/// stanje („Upravo svira"). Preljev u Flutteru je iznimka u testu, pa test
/// pada čim netko vrati `Row` bez `Expanded`/`Wrap` (isti razlog postojanja
/// kao `playback_bar_layout_test.dart`).
library;

import 'package:domovina_ai/l10n/app_localizations.dart';
import 'package:domovina_ai/models/sponsored_moment.dart';
import 'package:domovina_ai/services/sponsored_moments_controller.dart';
import 'package:domovina_ai/widgets/sponsored_moment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Točno na granici ugovora (brand ≤ 60, rečenica ≤ 120), od stvarnih riječi
/// da se prelamanje ponaša kao u životu.
String _words(int length) {
  const src = 'Hrvatska udruga proizvođača ekološke hrane i pića ';
  final b = StringBuffer();
  while (b.length < length) {
    b.write(src);
  }
  return b.toString().substring(0, length);
}

SponsoredMoment _worst({int start = 3600}) => SponsoredMoment(
  slotKey: 'v@$start',
  youtubeId: 'v',
  start: start,
  end: start + 600,
  brand: _words(60),
  tagline: _words(120),
  linkUrl: 'https://www.vrlo-dugacka-domena-proizvodaca-hrane.example.hr/x',
);

Widget _host(double width, Widget child, {Locale locale = const Locale('hr')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

void main() {
  setUp(SponsoredMomentsController.resetSessionForTest);

  for (final width in [320.0, 360.0]) {
    for (final locale in const [Locale('hr'), Locale('en')]) {
      testWidgets(
        'traka u playeru stane u $width dp (${locale.languageCode}), aktivna',
        (tester) async {
          final m = _worst();
          final c = SponsoredMomentsController(SponsoredMoments([m, _worst(start: 7200)]));
          c.onPosition(m.startPosition + const Duration(seconds: 1));
          expect(c.active.value, m);
          await tester.pumpWidget(
            _host(
              width,
              SponsoredMomentsPlayerStrip(controller: c, onListen: (_) {}),
              locale: locale,
            ),
          );
          expect(tester.takeException(), isNull);
          final l = await AppLocalizations.delegate.load(locale);
          expect(find.text(l.sponsoredNow), findsOneWidget);
          expect(find.textContaining(m.brand), findsWidgets);
        },
      );
    }

    testWidgets('oznaka u članku stane u $width dp', (tester) async {
      await tester.pumpWidget(
        _host(
          width,
          SponsoredMomentSectionMark(
            moments: [_worst(), _worst(start: 4000)],
            onListen: (_) {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('oznaka preko videa: najdulji brand se skrati, ne prelije', (
    tester,
  ) async {
    final m = _worst();
    final c = SponsoredMomentsController(SponsoredMoments([m]));
    c.onPosition(m.startPosition);
    await tester.pumpWidget(
      _host(
        320,
        SizedBox(
          height: 180,
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 8,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: SponsoredMomentVideoBadge(controller: c),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Sponzorirano · '), findsOneWidget);
  });

  testWidgets('oznaka preko videa ne postoji izvan trenutka', (tester) async {
    final m = _worst();
    final c = SponsoredMomentsController(SponsoredMoments([m]));
    c.onPosition(Duration.zero);
    await tester.pumpWidget(
      _host(320, SponsoredMomentVideoBadge(controller: c)),
    );
    expect(find.textContaining('Sponzorirano'), findsNothing);
  });

  testWidgets('bez trenutaka traka ne zauzima ništa', (tester) async {
    await tester.pumpWidget(
      _host(
        320,
        const SponsoredMomentsPlayerStrip(controller: null),
      ),
    );
    final size = tester.getSize(find.byType(SponsoredMomentsPlayerStrip));
    expect(size.height, 0);
  });
}
