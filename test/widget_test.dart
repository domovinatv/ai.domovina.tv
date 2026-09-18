import 'package:flutter_test/flutter_test.dart';
import 'package:domovina_ai/src/app.dart';

void main() {
  testWidgets('App smoke test — PodcastApp se gradi', (tester) async {
    await tester.pumpWidget(const PodcastApp());
    // Samo provjera da se widget tree gradi bez greske
    expect(find.byType(PodcastApp), findsOneWidget);
  });
}
