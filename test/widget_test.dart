import 'package:flutter_test/flutter_test.dart';
import 'package:domovina_ai/main.dart';

void main() {
  testWidgets('App smoke test — DominovinaApp se gradi', (tester) async {
    await tester.pumpWidget(const DominovinaApp());
    // Samo provjera da se widget tree gradi bez greske
    expect(find.byType(DominovinaApp), findsOneWidget);
  });
}
