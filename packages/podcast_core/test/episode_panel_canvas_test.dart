import 'package:podcast_core/widgets/episode_panel_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ugovor platna koje je 5.10.2026. zamijenilo drawer/endDrawer na epizodi:
/// panel GURA članak (nikad ne crta preko njega), u landscapeu stoje jedan uz
/// drugi, a panel ostaje montiran i kad je zatvoren (inače web `<video>`
/// putuje po DOM-u i pauzira se).
void main() {
  final key = GlobalKey<EpisodePanelCanvasState>();
  final changes = <EpisodePanelSide?>[];

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    changes.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EpisodePanelCanvas(
            key: key,
            onChanged: changes.add,
            center: const SizedBox.expand(key: Key('article')),
            left: const SizedBox.expand(key: Key('toc')),
            right: const SizedBox.expand(key: Key('player')),
          ),
        ),
      ),
    );
  }

  Rect rectOf(WidgetTester tester, String k) =>
      tester.getRect(find.byKey(Key(k)));

  testWidgets('landscape (844): članak i player stoje jedan uz drugi', (
    tester,
  ) async {
    await pump(tester, const Size(844, 390));
    key.currentState!.open(EpisodePanelSide.right);
    await tester.pumpAndSettle();

    expect(rectOf(tester, 'article'), const Rect.fromLTWH(0, 0, 484, 390));
    expect(rectOf(tester, 'player').left, 484);
    expect(rectOf(tester, 'player').right, 844);
    expect(changes, [EpisodePanelSide.right]);
  });

  testWidgets('portret (390): player gura članak, rub viri i zatvara tapom', (
    tester,
  ) async {
    await pump(tester, const Size(390, 844));
    key.currentState!.open(EpisodePanelSide.right);
    await tester.pumpAndSettle();

    // Članak zadrži punu širinu (nema reflowa), samo ode ulijevo.
    final article = rectOf(tester, 'article');
    expect(article.width, 390);
    expect(article.right, 32);
    expect(rectOf(tester, 'player').left, 32);

    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();
    expect(key.currentState!.isOpen, isFalse);
    expect(rectOf(tester, 'article').left, 0);
    expect(changes, [EpisodePanelSide.right, null]);
  });

  testWidgets('zatvoren panel ostaje montiran izvan ekrana', (tester) async {
    await pump(tester, const Size(390, 844));
    expect(find.byKey(const Key('player')), findsOneWidget);
    expect(rectOf(tester, 'player').left, 390);
    expect(find.byKey(const Key('toc')), findsOneWidget);
    expect(rectOf(tester, 'toc').right, 0);
  });

  testWidgets('otvaranje jednog panela zatvara drugi', (tester) async {
    await pump(tester, const Size(844, 390));
    key.currentState!.open(EpisodePanelSide.left);
    await tester.pumpAndSettle();
    expect(rectOf(tester, 'toc').left, 0);
    expect(rectOf(tester, 'article').left, 248);

    key.currentState!.toggle(EpisodePanelSide.right);
    await tester.pumpAndSettle();
    expect(rectOf(tester, 'toc').right, 0);
    expect(rectOf(tester, 'article').left, 0);
    expect(key.currentState!.openSide, EpisodePanelSide.right);
  });

  testWidgets('reflow centra: start vidi STARI raspored, kraj stiže jednom', (
    tester,
  ) async {
    final events = <String>[];
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final k = GlobalKey<EpisodePanelCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: EpisodePanelCanvas(
          key: k,
          center: const SizedBox.expand(key: Key('article')),
          right: const SizedBox.expand(key: Key('player')),
          onCenterReflowStart: () => events.add(
            'start:${tester.getSize(find.byKey(const Key('article'))).width}',
          ),
          onCenterReflow: () => events.add('reflow'),
          onCenterReflowEnd: () => events.add(
            'end:${tester.getSize(find.byKey(const Key('article'))).width}',
          ),
        ),
      ),
    );
    k.currentState!.open(EpisodePanelSide.right);
    await tester.pumpAndSettle();

    expect(events.first, 'start:844.0');
    expect(events.last, 'end:484.0');
    expect(events.where((e) => e.startsWith('start')), hasLength(1));
    expect(events.where((e) => e.startsWith('end')), hasLength(1));
    expect(events, contains('reflow'));
  });

  testWidgets('portret: panel koji GURA članak ne javlja reflow', (
    tester,
  ) async {
    var calls = 0;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final k = GlobalKey<EpisodePanelCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: EpisodePanelCanvas(
          key: k,
          center: const SizedBox.expand(),
          right: const SizedBox.expand(),
          onCenterReflowStart: () => calls++,
        ),
      ),
    );
    k.currentState!.open(EpisodePanelSide.right);
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('povlačenje od desnog ruba udesno NE otvara lijevi panel', (
    tester,
  ) async {
    await pump(tester, const Size(844, 390));
    await tester.dragFrom(const Offset(835, 200), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(key.currentState!.isOpen, isFalse);
    expect(rectOf(tester, 'toc').right, 0);

    // Isti rub ulijevo otvara player.
    await tester.dragFrom(const Offset(835, 200), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(key.currentState!.openSide, EpisodePanelSide.right);
  });

  testWidgets('otvoren panel koji nestane resetira stanje i javi null', (
    tester,
  ) async {
    final reported = <EpisodePanelSide?>[];
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final k = GlobalKey<EpisodePanelCanvasState>();
    Widget app({required bool withPlayer}) => MaterialApp(
      home: EpisodePanelCanvas(
        key: k,
        onChanged: reported.add,
        center: const SizedBox.expand(key: Key('article')),
        right: withPlayer ? const SizedBox.expand() : null,
      ),
    );
    await tester.pumpWidget(app(withPlayer: true));
    k.currentState!.open(EpisodePanelSide.right);
    await tester.pumpAndSettle();

    // Npr. iPad zarotiran preko 1100 px: player postaje stalni stupac.
    await tester.pumpWidget(app(withPlayer: false));
    await tester.pumpAndSettle();
    expect(k.currentState!.isOpen, isFalse);
    expect(reported, [EpisodePanelSide.right, null]);
    expect(tester.getRect(find.byKey(const Key('article'))).width, 844);
  });

  testWidgets('zatvoren panel je izvan semantičkog stabla', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    final k = GlobalKey<EpisodePanelCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: EpisodePanelCanvas(
          key: k,
          center: const SizedBox.expand(),
          right: const Text('Kontrole playera'),
        ),
      ),
    );
    expect(find.semantics.byLabel('Kontrole playera'), findsNothing);
    k.currentState!.open(EpisodePanelSide.right);
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('Kontrole playera'), findsOne);
    handle.dispose();
  });

  testWidgets('panel koji nestane ne javlja reflow usred buildanja', (
    tester,
  ) async {
    final events = <String>[];
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final k = GlobalKey<EpisodePanelCanvasState>();
    Widget app({required bool withPlayer}) => MaterialApp(
      home: EpisodePanelCanvas(
        key: k,
        center: const SizedBox.expand(),
        right: withPlayer ? const SizedBox.expand() : null,
        onCenterReflowStart: () => events.add('start'),
        onCenterReflowEnd: () => events.add('end'),
      ),
    );
    await tester.pumpWidget(app(withPlayer: true));
    k.currentState!.open(EpisodePanelSide.right);
    await tester.pumpAndSettle();
    events.clear();

    await tester.pumpWidget(app(withPlayer: false));
    await tester.pumpAndSettle();
    expect(events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uski landscape (667, iPhone SE): player se suzi, ne gura', (
    tester,
  ) async {
    await pump(tester, const Size(667, 375));
    key.currentState!.open(EpisodePanelSide.right);
    await tester.pumpAndSettle();
    final article = rectOf(tester, 'article');
    expect(article.left, 0);
    expect(article.width, 320);
    expect(rectOf(tester, 'player').width, 347);
  });

  testWidgets('iPhone 13 landscape (750): članak 390 uz player 360', (
    tester,
  ) async {
    await pump(tester, const Size(750, 342));
    key.currentState!.open(EpisodePanelSide.right);
    await tester.pumpAndSettle();
    expect(rectOf(tester, 'article'), const Rect.fromLTWH(0, 0, 390, 342));
  });
}
