/// Kontrakt obrasca za podršku nakon redizajna (2026-08-08, T2):
/// - tri polja (Ime / Poveznica / Poruka) nose `labelText`, pa oznaka ostaje
///   vidljiva i NAKON što korisnik utipka tekst (hint bi nestao),
/// - živi pregled kartice pokazuje točan ishod prije plaćanja,
/// - kvačica "anonimno" prebaci pregled na "Anoniman".
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/l10n/app_localizations.dart';
import 'package:domovina_ai/pinka_sdk/src/models/pinka_campaign.dart';
import 'package:domovina_ai/pinka_sdk/src/models/pinka_contribution_intent.dart';
import 'package:domovina_ai/pinka_sdk/src/pinka_client.dart';
import 'package:domovina_ai/pinka_sdk/src/pinka_config.dart';
import 'package:domovina_ai/pinka_sdk/src/widgets/pinka_contribute_panel.dart';

/// Donacijska kampanja bez Safe adrese → samo SEPA (bez mode togglea), pa je
/// obrazac s identitetom vidljiv odmah.
const _campaign = PinkaCampaign(
  id: 'c1',
  slug: 'test-kampanja',
  type: 'donation',
  title: 'Test kampanja',
  description: null,
  goalCents: null,
  minContributionCents: 100,
  currency: 'eur',
  coverImageUrl: null,
  state: 'active',
  destinationAddress: null,
  chain: 'gnosis',
  totalRaisedCents: 0,
  contributionCount: 0,
  contributorCount: 0,
);

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('hr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Widget _panel() => PinkaContributePanel(
      campaign: _campaign,
      client: PinkaClient(),
      config: PinkaConfig.defaults,
    );

/// Nađi polje po njegovoj oznaci (redoslijed `TextField`-ova nije ugovor).
Finder _fieldWithLabel(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));

Finder _inPreview(Finder matching) => find.descendant(
      of: find.byKey(const Key('pinka-preview-card')),
      matching: matching,
    );

/// Presretne `contribute` da test vidi ŠTO se šalje, pa baci — panel tada
/// samo prikaže grešku i ne pokrene ni jedan timer (nema pending-timer pada).
class _CapturingClient extends PinkaClient {
  String? sentMessage;
  String? sentLinkUrl;
  bool called = false;

  @override
  Future<PinkaContributionIntent> contribute({
    required String campaignId,
    required int amountCents,
    String? displayName,
    String? message,
    String? linkUrl,
    bool anonymous = false,
    List<String>? slotKeys,
  }) async {
    called = true;
    sentMessage = message;
    sentLinkUrl = linkUrl;
    throw PinkaFailure('captured');
  }
}

void main() {
  testWidgets('sve tri oznake ostaju vidljive nakon unosa teksta',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final l = await AppLocalizations.delegate.load(const Locale('hr'));

    await tester.pumpWidget(_wrap(_panel()));
    await tester.pumpAndSettle();

    await tester.enterText(_fieldWithLabel(l.pinkaNameLabel), 'Ana Anić');
    await tester.enterText(_fieldWithLabel(l.pinkaLinkLabel), 'domovina.ai');
    await tester.enterText(_fieldWithLabel(l.pinkaMessageLabel), 'Hvala vam!');
    await tester.pumpAndSettle();

    expect(find.text(l.pinkaNameLabel), findsOneWidget);
    expect(find.text(l.pinkaLinkLabel), findsOneWidget);
    expect(find.text(l.pinkaMessageLabel), findsOneWidget);
  });

  testWidgets('pregled prikazuje upisano ime, iznos i host poveznice',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final l = await AppLocalizations.delegate.load(const Locale('hr'));

    await tester.pumpWidget(_wrap(_panel()));
    await tester.pumpAndSettle();

    // Prazna polja → prigušeni placeholderi, bez lažnog sadržaja.
    expect(_inPreview(find.text(l.pinkaPreviewNamePlaceholder)), findsOneWidget);
    expect(_inPreview(find.text(l.pinkaPreviewMessagePlaceholder)),
        findsOneWidget);

    await tester.enterText(_fieldWithLabel(l.pinkaNameLabel), 'Ana Anić');
    await tester.enterText(_fieldWithLabel(l.pinkaLinkLabel), 'domovina.ai');
    await tester.pumpAndSettle();

    expect(_inPreview(find.text('Ana Anić')), findsOneWidget);
    // Default iznos 5,00 € — isti tekst nosi i preset čip, zato scopeano.
    expect(_inPreview(find.text('5 €')), findsOneWidget);
    expect(_inPreview(find.text('domovina.ai')), findsOneWidget);
    expect(_inPreview(find.text(l.pinkaPreviewNamePlaceholder)), findsNothing);
  });

  testWidgets('kvačica "anonimno" prebaci pregled na Anoniman',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final l = await AppLocalizations.delegate.load(const Locale('hr'));

    await tester.pumpWidget(_wrap(_panel()));
    await tester.pumpAndSettle();

    await tester.enterText(_fieldWithLabel(l.pinkaNameLabel), 'Ana Anić');
    await tester.pumpAndSettle();
    expect(_inPreview(find.text('Ana Anić')), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(_inPreview(find.text(l.pinkaAnonymous)), findsOneWidget);
    expect(_inPreview(find.text('Ana Anić')), findsNothing);
  });

  testWidgets('poveznica ide i u link_url i (kao most) na kraj poruke',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final l = await AppLocalizations.delegate.load(const Locale('hr'));
    final client = _CapturingClient();

    await tester.pumpWidget(_wrap(PinkaContributePanel(
      campaign: _campaign,
      client: client,
      config: PinkaConfig.defaults,
    )));
    await tester.pumpAndSettle();

    await tester.enterText(_fieldWithLabel(l.pinkaNameLabel), 'Ana Anić');
    await tester.enterText(_fieldWithLabel(l.pinkaLinkLabel), 'domovina.ai');
    await tester.enterText(_fieldWithLabel(l.pinkaMessageLabel), 'Hvala!');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(client.sentLinkUrl, 'https://domovina.ai');
    // OG preview u `pinka-webhook` još čita SAMO `message` — bez appenda bi
    // poveznica nestala (regresija).
    expect(client.sentMessage, 'Hvala! https://domovina.ai');
  });

  testWidgets('nevaljana poveznica blokira slanje i javi grešku',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final l = await AppLocalizations.delegate.load(const Locale('hr'));
    final client = _CapturingClient();

    await tester.pumpWidget(_wrap(PinkaContributePanel(
      campaign: _campaign,
      client: client,
      config: PinkaConfig.defaults,
    )));
    await tester.pumpAndSettle();

    await tester.enterText(_fieldWithLabel(l.pinkaLinkLabel), 'moja stranica');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(client.called, isFalse);
    expect(find.text(l.pinkaLinkInvalid), findsOneWidget);
  });
}
