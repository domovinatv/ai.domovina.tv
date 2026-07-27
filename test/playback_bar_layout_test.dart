/// Širinski budžet media_kitove `bottomButtonBar` u najužem stvarnom slučaju.
///
/// Zašto test, a ne oko: media_kit slaže traku u goli `Row` bez zaštite od
/// preljeva, a desktop varijanta živi u 360 dp `VideoPanel` stupcu. Kad je
/// T3 ondje dodao gumb brzine i gumb „u pozadini", sedam gumba po 48 dp
/// prešlo je raspoloživih 328 dp (360 − 2×16 dp margine media_kita) i traka
/// je pukla za točno 8 dp. Kontrolni slučaj na dnu čuva upravo tu aritmetiku:
/// ako netko makne elastični slot ili kompaktne 40 dp slotove, test to
/// prijavi.
///
/// Geometrija je preslikana iz
/// `media_kit_video/.../controls/material_desktop.dart` (Container s
/// `bottomButtonBarMargin` → `Row(mainAxisSize: max)`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/l10n/app_localizations.dart';
import 'package:domovina_ai/widgets/playback_controls.dart';

/// Najuži stvarni kontekst: `VideoPanel` stupac je 360 dp.
const _panelWidth = 360.0;

/// Najuži telefon koji podržavamo.
const _phoneWidth = 320.0;

Widget _bar(double width, List<Widget> children) => MaterialApp(
      locale: const Locale('hr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Container(
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );

/// Ista tri omotača kao u `episode_video.dart`.
Widget _positionSlot(String label) => Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(label, style: const TextStyle(height: 1.0, fontSize: 12)),
      ),
    );

Widget _compactSlot(Widget child) => SizedBox(
      width: 40,
      child: FittedBox(fit: BoxFit.scaleDown, child: child),
    );

Widget _speed() => _compactSlot(const SpeedCycleButton(onVideo: true));

Widget _background() =>
    _compactSlot(const BackgroundPlaybackButton(onVideo: true));

/// media_kitovi gumbi — svi završe na 48 dp (IconButton minimum), bez obzira
/// na `iconSize`.
Widget _mkButton(double iconSize) => IconButton(
      iconSize: iconSize,
      onPressed: () {},
      icon: const Icon(Icons.circle),
    );

/// Najduži realan label indikatora pozicije (epizoda preko sat vremena).
const _longestClock = '1:02:03 / 1:45:22';

void main() {
  testWidgets('desktop traka u 360 dp panelu stane — puna postava', (
    tester,
  ) async {
    await tester.pumpWidget(
      _bar(_panelWidth, [
        _mkButton(28), // play/pause
        _mkButton(28), // volume
        _positionSlot(_longestClock),
        _speed(),
        _background(),
        _mkButton(24), // YouTube embed
        _mkButton(24), // CC
        _mkButton(28), // fullscreen
      ]),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobilna traka na 320 dp stane — puna postava', (tester) async {
    await tester.pumpWidget(
      _bar(_phoneWidth, [
        _positionSlot(_longestClock),
        _speed(),
        _background(),
        _mkButton(24), // YouTube embed
        _mkButton(24), // CC
        _mkButton(24), // fullscreen
      ]),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'kontrolni slučaj: bez elastičnog slota i kompaktne gustoće traka pukne',
    (tester) async {
      await tester.pumpWidget(
        _bar(_panelWidth, [
          _mkButton(28),
          _mkButton(28),
          const Text(
            _longestClock,
            style: TextStyle(height: 1.0, fontSize: 12),
          ),
          const Spacer(),
          const SpeedCycleButton(onVideo: true),
          const BackgroundPlaybackButton(onVideo: true),
          _mkButton(24),
          _mkButton(24),
          _mkButton(28),
        ]),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNotNull);
    },
  );
}
