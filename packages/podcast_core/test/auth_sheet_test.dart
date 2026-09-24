/// Kontrakt prijavnog lista nakon UI/UX prolaza (2026-07-25):
/// - "gost" traka se vidi samo neprijavljenom korisniku,
/// - sheet ima uvijek dostupan ✕ (iOS: drag handle zna završiti pod
///   Dynamic Islandom),
/// - back na pod-koraku vraća korak, ne zatvara cijeli flow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/onboarding/ui/auth_sheet.dart';
import 'package:podcast_core/widgets/anonymous_signin_bar.dart';

import 'support/fake_asset_bundle.dart';
import 'support/test_brands.dart';

Widget _wrap(Widget child) => DefaultAssetBundle(
      // Brend asseti su u ljusci, ne u paketu — vidi support/fake_asset_bundle.dart.
      bundle: FakeAssetBundle(),
      child: MaterialApp(
        locale: const Locale('hr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('AnonymousSignInBar se prikaže neprijavljenom korisniku',
      (tester) async {
    await tester.pumpWidget(_wrap(const AnonymousSignInBar()));
    await tester.pump();

    final l = await AppLocalizations.delegate.load(const Locale('hr'));
    expect(find.text(l.authGuestBarTitle), findsOneWidget);
    expect(find.text(l.commonSignIn), findsOneWidget);
  });

  testWidgets('sheet: ✕ zatvara, back na e-mail koraku vraća na providere',
      (tester) async {
    final l = await AppLocalizations.delegate.load(const Locale('hr'));

    await tester.pumpWidget(_wrap(
      Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => showAuthSheet(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(l.authContinueWithGoogle), findsOneWidget);

    // ✕ mora postojati na koraku s providerima (jedini pouzdan izlaz na iOS-u).
    expect(find.byIcon(Icons.close), findsOneWidget);

    // E-mail tile → korak s unosom e-maila.
    await tester.ensureVisible(find.text(l.authEmailMagicLink));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.authEmailMagicLink));
    await tester.pumpAndSettle();
    expect(find.text(l.authSendCode), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // Back vraća KORAK, ne zatvara sheet.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text(l.authContinueWithGoogle), findsOneWidget);
    expect(find.text(l.authSendCode), findsNothing);

    // ✕ zatvara cijeli sheet.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text(l.authContinueWithGoogle), findsNothing);
  });

  testWidgets('e-mail korak vodi na prijavu lozinkom, back vraća na e-mail',
      (tester) async {
    final l = await AppLocalizations.delegate.load(const Locale('hr'));
    await tester.pumpWidget(_wrap(
      Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => showAuthSheet(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l.authEmailMagicLink));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.authEmailMagicLink));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l.authUsePassword));
    await tester.pumpAndSettle();
    expect(find.text(l.authPasswordHint), findsOneWidget);
    expect(find.text(l.commonSignIn), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text(l.authSendCode), findsOneWidget);
    expect(find.text(l.authPasswordHint), findsNothing);
  });

  group('passkeys po brendu', () {
    tearDown(() => AppBrand.init(domovinaBrand));

    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showAuthSheet(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('DOMOVINA nudi passkey', (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      await openSheet(tester);
      expect(find.text(l.authSignInWithPasskey), findsOneWidget);
    });

    testWidgets('brend bez passkeyja ne nudi passkey, Google vodi',
        (tester) async {
      AppBrand.init(brandWithoutPasskeys());
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      await openSheet(tester);
      expect(find.text(l.authSignInWithPasskey), findsNothing);
      expect(find.text(l.authContinueWithGoogle), findsOneWidget);
    });
  });
}
