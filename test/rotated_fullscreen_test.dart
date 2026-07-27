/// Rotacijski fullscreen (T4) — dva sloja testova.
///
/// **1. PROBA (gate)**: dokazuje da `RotatedBox` rotira i hit-testing, ne samo
/// piksele — inače rotacijski fullscreen traži ručno preračunavanje koordinata
/// i task se zaustavlja (vidi docs/plans/2026-07-27-playback-overhaul.md, T4).
/// Minimalni probni ekran: portretni viewport 400×800 dp, unutra
/// `RotatedBox(quarterTurns: 1)` (90° u smjeru kazaljke) s djetetom koje je
/// logički landscape (800×400). Meta je u GORNJEM LIJEVOM kutu djeteta — nakon
/// rotacije mora primati tapove u GORNJEM DESNOM kutu ekrana.
///
/// **2. Ruta i sadržaj**: `RotatedFullscreenView` (rotira samo u portretu,
/// popravlja `MediaQuery`) i `showRotatedFullscreen` (izlaz gumbom, Backom,
/// jednokratni `onClosed`).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/widgets/rotated_fullscreen.dart';

void main() {
  const portrait = Size(400, 800);

  /// Probni ekran: RotatedBox preko cijelog portretnog viewporta, dijete
  /// dobiva zamijenjene constraintove (800×400) pa je logički landscape.
  Widget probe({
    required Widget target,
    Alignment targetAlignment = Alignment.topLeft,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(
          child: RotatedBox(
            quarterTurns: 1,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: Colors.black)),
                Align(alignment: targetAlignment, child: target),
              ],
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    // Portretni viewport, dpr 1 → dp koordinate = piksel koordinate.
  });

  testWidgets('dijete RotatedBoxa dobiva zamijenjene constraintove',
      (tester) async {
    tester.view.physicalSize = portrait;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      probe(target: SizedBox(key: key, width: 60, height: 40)),
    );

    // Sam RotatedBox pokriva cijeli portret…
    expect(tester.getSize(find.byType(RotatedBox)), portrait);
    // …a Stack unutra je landscape (constraintovi zamijenjeni).
    final stackSize = tester.getSize(find.byType(Stack).first);
    expect(stackSize, const Size(800, 400));
    expect(key.currentContext, isNotNull);
  });

  testWidgets('TAP: meta u gornjem lijevom kutu djeteta prima tap u gornjem '
      'desnom kutu ekrana (rotacija hit-testinga radi)', (tester) async {
    tester.view.physicalSize = portrait;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var taps = 0;
    await tester.pumpWidget(
      probe(
        target: GestureDetector(
          onTap: () => taps++,
          child: Container(width: 120, height: 80, color: Colors.red),
        ),
      ),
    );

    // Gdje Flutter MISLI da meta jest u globalnim (ekranskim) koordinatama.
    final rect = tester.getRect(find.byType(Container).last);
    // 120×80 dijete u gornjem lijevom kutu landscape djeteta → nakon 90° CW
    // to je gornji DESNI kut portretnog ekrana, 80 široko × 120 visoko.
    expect(rect.width, 80);
    expect(rect.height, 120);
    expect(rect.right, 400);
    expect(rect.top, 0);

    // Tap po SIROVIM ekranskim koordinatama (ne preko find-a) — ovo je pravi
    // dokaz: hit-test putanja sama transformira pointer u prostor djeteta.
    await tester.tapAt(const Offset(390, 10)); // gornji desni kut ekrana
    await tester.pump();
    expect(taps, 1, reason: 'rotirani hit-test ne prima tap na svom mjestu');

    // Kontrola: gornji LIJEVI kut ekrana (gdje meta vizualno NIJE) ne smije
    // pogoditi — da test ne prolazi zato što meta pokriva sve.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(taps, 1, reason: 'hit-test pogađa i tamo gdje meta nije nacrtana');
  });

  testWidgets('DRAG: vertikalni potez po ekranu je horizontalni potez u '
      'prostoru djeteta (slider/seek bar radi bez preračunavanja)',
      (tester) async {
    tester.view.physicalSize = portrait;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var horizontalDelta = 0.0;
    var horizontalDrags = 0;
    await tester.pumpWidget(
      probe(
        targetAlignment: Alignment.center,
        target: GestureDetector(
          onHorizontalDragStart: (_) => horizontalDrags++,
          onHorizontalDragUpdate: (d) => horizontalDelta += d.delta.dx,
          child: Container(width: 400, height: 200, color: Colors.blue),
        ),
      ),
    );

    // Meta je u sredini; potez povlačimo po ekranu VERTIKALNO (prema dolje).
    // U prostoru djeteta to mora izaći kao horizontalni potez UDESNO.
    final center = tester.getCenter(find.byType(Container).last);
    await tester.dragFrom(center, const Offset(0, 120));
    await tester.pump();

    expect(horizontalDrags, 1,
        reason: 'GestureDetector u rotiranom prostoru nije prepoznao potez');
    expect(horizontalDelta, closeTo(120, 0.01),
        reason: 'delta poteza nije transformirana u prostor djeteta');
  });

  testWidgets('SLIDER: povlačenje pravog Slidera u rotiranom prostoru mijenja '
      'vrijednost u ispravnom smjeru', (tester) async {
    tester.view.physicalSize = portrait;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var value = 0.5;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: RotatedBox(
              quarterTurns: 1,
              child: StatefulBuilder(
                builder: (context, setState) => Center(
                  child: SizedBox(
                    width: 600,
                    child: Slider(
                      value: value,
                      onChanged: (v) => setState(() => value = v),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final knob = tester.getCenter(find.byType(Slider));
    // Ekranski potez PREMA DOLJE = udesno u prostoru djeteta = veća vrijednost.
    final gesture = await tester.startGesture(knob, kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(value, greaterThan(0.5),
        reason: 'Slider u rotiranom prostoru ne prati potez');
  });

  // -------------------------------------------------------------------------
  // RotatedFullscreenView
  // -------------------------------------------------------------------------

  /// Vrti `RotatedFullscreenView` u zadanom viewportu i vrati `MediaQueryData`
  /// koji vidi dijete (sadržaj rotirane rute).
  Future<MediaQueryData> viewIn(
    WidgetTester tester,
    Size viewport, {
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    MediaQueryData? seen;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: viewport, padding: padding),
          child: RotatedFullscreenView(
            child: Builder(
              builder: (context) {
                seen = MediaQuery.of(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    return seen!;
  }

  testWidgets('portretni viewport → rotira i preslika MediaQuery', (tester) async {
    final seen = await viewIn(
      tester,
      const Size(400, 800),
      // Notch gore, home indicator dolje — kao iPhone u portretu.
      padding: const EdgeInsets.only(top: 47, bottom: 34, left: 3, right: 4),
    );

    expect(find.byType(RotatedBox), findsOneWidget);
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 1);

    // Dijete radi u landscape prostoru…
    expect(seen.size, const Size(800, 400));
    // …a insete dobiva na rubovima na koje se preslikaju ekranski (90° CW:
    // gornji rub ekrana → lijevi rub djeteta, desni → gornji, itd.).
    expect(seen.padding.left, 47);
    expect(seen.padding.top, 4);
    expect(seen.padding.right, 34);
    expect(seen.padding.bottom, 3);
  });

  testWidgets('landscape viewport → NE rotira (inače dvostruka rotacija)',
      (tester) async {
    final seen = await viewIn(tester, const Size(800, 400));

    expect(find.byType(RotatedBox), findsNothing);
    expect(seen.size, const Size(800, 400));
  });

  // -------------------------------------------------------------------------
  // showRotatedFullscreen
  // -------------------------------------------------------------------------

  testWidgets('ruta: otvori, exit() zatvori, onClosed točno jednom',
      (tester) async {
    tester.view.physicalSize = portrait;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var closed = 0;
    VoidCallback? capturedExit;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showRotatedFullscreen(
                  context: context,
                  onOpened: (exit) => capturedExit = exit,
                  builder: (_, exit) => ElevatedButton(
                    onPressed: exit,
                    child: const Text('izlaz'),
                  ),
                  onClosed: () => closed++,
                ),
                child: const Text('otvori'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('otvori'));
    await tester.pumpAndSettle();

    expect(find.text('izlaz'), findsOneWidget);
    expect(find.text('otvori'), findsNothing, reason: 'ruta nije opaque');
    expect(capturedExit, isNotNull,
        reason: 'onOpened mora dati exit PRIJE pusha');
    expect(closed, 0);

    // Izlaz gumbom iz sadržaja rute.
    await tester.tap(find.text('izlaz'));
    await tester.pumpAndSettle();

    expect(find.text('izlaz'), findsNothing);
    expect(find.text('otvori'), findsOneWidget);
    expect(closed, 1);

    // Ponovni exit na već zatvorenoj ruti ne smije ništa dirati.
    capturedExit!();
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('ruta: sistemski Back zatvara i javlja onClosed', (tester) async {
    tester.view.physicalSize = portrait;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showRotatedFullscreen(
                context: context,
                builder: (_, _) => const Text('u fullscreenu'),
                onClosed: () => closed++,
              ),
              child: const Text('otvori'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('otvori'));
    await tester.pumpAndSettle();
    expect(find.text('u fullscreenu'), findsOneWidget);

    // Sistemska Back tipka — obična ruta se popa sama, bez PopScope-a.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('u fullscreenu'), findsNothing);
    expect(closed, 1);
  });
}
