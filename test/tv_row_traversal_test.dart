import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/screens/tv/widgets/tv_row_traversal.dart';

/// Regresija za D-pad preskakanje raila na TV-u: rail s malo kartica uz lijevi
/// rub (lane „Osobe") ne smije se preskočiti kad se silazi iz sredine šireg
/// raila iznad. Layout u testu je namjerno isti oblik kao TV home:
///
///   redak A: tri kartice preko cijele širine  (npr. „Najnovije epizode")
///   redak B: JEDNA kartica uz lijevi rub      (lane „Osobe")
///   redak C: tri kartice preko cijele širine  (mreža „Kanali")
void main() {
  Widget harness(Map<String, Rect> boxes, Map<String, FocusNode> nodes) {
    return MaterialApp(
      home: Scaffold(
        body: FocusTraversalGroup(
          policy: TvRowTraversalPolicy(),
          child: Stack(
            children: [
              for (final entry in boxes.entries)
                Positioned.fromRect(
                  rect: entry.value,
                  child: Focus(
                    focusNode: nodes[entry.key],
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  late Map<String, FocusNode> nodes;
  final boxes = <String, Rect>{
    'a1': const Rect.fromLTWH(0, 0, 100, 50),
    'a2': const Rect.fromLTWH(200, 0, 100, 50),
    'a3': const Rect.fromLTWH(400, 0, 100, 50),
    'b1': const Rect.fromLTWH(0, 100, 100, 50),
    'c1': const Rect.fromLTWH(0, 200, 100, 50),
    'c2': const Rect.fromLTWH(200, 200, 100, 50),
    'c3': const Rect.fromLTWH(400, 200, 100, 50),
  };

  setUp(() {
    nodes = {
      for (final key in boxes.keys) key: FocusNode(debugLabel: key),
    };
  });

  tearDown(() {
    for (final node in nodes.values) {
      node.dispose();
    }
  });

  testWidgets('DOLJE s desne kartice ulazi u rail s jednom karticom, ne preskače ga',
      (tester) async {
    await tester.pumpWidget(harness(boxes, nodes));
    nodes['a3']!.requestFocus();
    await tester.pump();

    final policy = TvRowTraversalPolicy();
    expect(
      policy.inDirection(nodes['a3']!, TraversalDirection.down),
      isTrue,
    );
    await tester.pump();
    expect(nodes['b1']!.hasFocus, isTrue,
        reason: 'redak s jednom karticom mora primiti fokus');
  });

  testWidgets('GORE iz mreže vraća na rail s jednom karticom', (tester) async {
    await tester.pumpWidget(harness(boxes, nodes));
    nodes['c3']!.requestFocus();
    await tester.pump();

    TvRowTraversalPolicy().inDirection(nodes['c3']!, TraversalDirection.up);
    await tester.pump();
    expect(nodes['b1']!.hasFocus, isTrue);
  });

  testWidgets('DOLJE unutar punih redaka zadržava stupac', (tester) async {
    await tester.pumpWidget(harness(boxes, nodes));
    nodes['b1']!.requestFocus();
    await tester.pump();

    TvRowTraversalPolicy().inDirection(nodes['b1']!, TraversalDirection.down);
    await tester.pump();
    expect(nodes['c1']!.hasFocus, isTrue,
        reason: 'isti stupac ima prednost pred udaljenošću središta');
  });

  testWidgets('na rubu ekrana intent se ne obrađuje (fokus ostaje)',
      (tester) async {
    await tester.pumpWidget(harness(boxes, nodes));
    nodes['a2']!.requestFocus();
    await tester.pump();

    expect(
      TvRowTraversalPolicy().inDirection(nodes['a2']!, TraversalDirection.up),
      isFalse,
    );
    await tester.pump();
    expect(nodes['a2']!.hasFocus, isTrue);
  });

  testWidgets('GORE iz prvog reda mreže dohvaća NATRAG iznad scrollabla',
      (tester) async {
    // Oblik TvPersonScreen/TvChannelScreen: fiksni appbar u Columnu + mreža u
    // Expanded scrollablu. Bez politike ovo je bio slijepi kut — fokus je
    // ostajao na kartici.
    final back = FocusNode(debugLabel: 'back');
    final cards = List.generate(6, (i) => FocusNode(debugLabel: 'card$i'));
    addTearDown(() {
      back.dispose();
      for (final c in cards) {
        c.dispose();
      }
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FocusTraversalGroup(
          policy: TvRowTraversalPolicy(),
          child: Column(
            children: [
              SizedBox(
                height: 60,
                child: Row(
                  children: [
                    Focus(
                      focusNode: back,
                      child: const SizedBox(width: 120, height: 40),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisExtent: 120,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => Focus(
                          focusNode: cards[i],
                          child: const SizedBox.expand(),
                        ),
                        childCount: cards.length,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    // Sredina prvog reda → GORE mora doći na NATRAG iako se stupci ne poklapaju.
    cards[1].requestFocus();
    await tester.pump();
    TvRowTraversalPolicy().inDirection(cards[1], TraversalDirection.up);
    await tester.pump();
    expect(back.hasFocus, isTrue);

    // I natrag dolje u prvi red mreže.
    TvRowTraversalPolicy().inDirection(back, TraversalDirection.down);
    await tester.pump();
    expect(cards[0].hasFocus, isTrue);
  });

  testWidgets('kad se nijedan kandidat ne preklapa, bira najbliži po rubu',
      (tester) async {
    // Redak B pomaknut skroz desno; fokus dolazi s lijeve kartice retka A.
    final shifted = Map<String, Rect>.from(boxes)
      ..['b1'] = const Rect.fromLTWH(400, 100, 100, 50);
    await tester.pumpWidget(harness(shifted, nodes));
    nodes['a1']!.requestFocus();
    await tester.pump();

    TvRowTraversalPolicy().inDirection(nodes['a1']!, TraversalDirection.down);
    await tester.pump();
    expect(nodes['b1']!.hasFocus, isTrue,
        reason: 'redak se ne preskače ni kad nema preklapanja stupaca');
  });
}
