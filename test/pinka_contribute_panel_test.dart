/// Kontrakt obrasca za podršku nakon redizajna (2026-08-08, T2):
/// - tri polja (Ime / Poveznica / Poruka) nose `labelText`, pa oznaka ostaje
///   vidljiva i NAKON što korisnik utipka tekst (hint bi nestao),
/// - živi pregled kartice pokazuje točan ishod prije plaćanja,
/// - kvačica "anonimno" prebaci pregled na "Anoniman".
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/l10n/app_localizations.dart';
import 'package:domovina_ai/pinka_sdk/src/models/pinka_campaign.dart';
import 'package:domovina_ai/pinka_sdk/src/models/pinka_contribution_intent.dart';
import 'package:domovina_ai/pinka_sdk/src/pinka_client.dart';
import 'package:domovina_ai/pinka_sdk/src/pinka_config.dart';
import 'package:domovina_ai/pinka_sdk/src/util/pinka_intent_status.dart';
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

/// SEPA tok bez mreže: `contribute` vrati intent sa status URL-om, RPC
/// `contribution_status` čita [rpcState]. `waitForPaid` je PRAVI (s fake
/// asyncom), pa test mjeri i da petlja nema limit.
class _SepaClient extends PinkaClient {
  String rpcState = 'pending';
  int rpcCalls = 0;

  @override
  Future<PinkaContributionIntent> contribute({
    required String campaignId,
    required int amountCents,
    String? displayName,
    String? message,
    String? linkUrl,
    bool anonymous = false,
    List<String>? slotKeys,
  }) async =>
      const PinkaContributionIntent(
        contributionId: 'contrib-1',
        sid: 'sid-1',
        amountEur: '5.00',
        amountCents: 500,
        currency: 'eur',
        memo: 'PINKA sid-1',
        iban: 'HR1210010051863000160',
        beneficiaryName: 'Test',
        bic: 'TESTHR2X',
        epcQrData: 'BCD',
        checkoutUrl: 'https://pay.test/sid-1',
        statusUrl: 'https://rail.test/api/intents/sid-1',
        expiresAt: null,
      );

  @override
  Future<String?> contributionStatus(String contributionId) async {
    rpcCalls++;
    return rpcState;
  }
}

/// Lažni rail: vraća [stage] (+ razlog) i broji dohvate.
class _FakeRail {
  String stage = 'awaiting_payment';
  String? reason;
  bool? reviewExpected;
  int calls = 0;

  Future<PinkaIntentStatus?> fetch(String url) async {
    calls++;
    return PinkaIntentStatus(
      stage: stage,
      rejectedReason: reason,
      reviewExpected: reviewExpected,
      steps: const [
        PinkaIntentStep(key: 'payment', status: 'proven'),
        PinkaIntentStep(key: 'processing', status: 'in_progress'),
        PinkaIntentStep(key: 'minted', status: 'waiting'),
        PinkaIntentStep(key: 'forwarding', status: 'waiting'),
        PinkaIntentStep(key: 'settled', status: 'waiting'),
      ],
    );
  }
}

class _SepaHarness {
  final client = _SepaClient();
  final rail = _FakeRail();
  int paidCalls = 0;
  int haptics = 0;

  Widget panel() => PinkaContributePanel(
        campaign: _campaign,
        client: client,
        config: PinkaConfig.defaults,
        statusFetcher: rail.fetch,
        onPaid: (_, _) => paidCalls++,
      );

  Future<void> start(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(_wrap(panel()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump();
  }

  /// Jedan krug pollinga (rail + RPC su oba na 3 s).
  Future<void> tick(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  }

  /// Ugasi widget i pusti da `waitForPaid` izađe kroz `isCancelled` — inače
  /// test padne na "Timer is still pending".
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  }
}

double _successIconScale(WidgetTester tester) {
  final t = tester.widget<Transform>(find.descendant(
    of: find.byType(TweenAnimationBuilder<double>),
    matching: find.byType(Transform),
  ));
  return t.transform.getMaxScaleOnAxis();
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

  group('SEPA: uspjeh na zaprimanju, namira kasnije', () {
    testWidgets('uspjeh na received_processing PRIJE RPC paid', (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      final h = _SepaHarness();
      await h.start(tester);
      expect(find.text(l.pinkaScanInBankApp), findsOneWidget);

      h.rail.stage = 'received_processing';
      await h.tick(tester);

      expect(find.text(l.pinkaThanksForSupport), findsOneWidget);
      expect(find.text(l.pinkaSepaReceivedProcessing), findsOneWidget);
      expect(find.text(l.pinkaSepaFirstPaymentReview), findsOneWidget);
      expect(find.text(l.pinkaPaymentConfirmedOnchain), findsNothing);
      // Doprinos u bazi još nije `paid` → zid se ne dira.
      expect(h.paidCalls, 0);
      expect(h.haptics, 1);

      // Nakon 60 s u istoj fazi napomena o prvoj uplati se ističe.
      expect(find.byKey(const Key('pinka-first-payment-review')), findsNothing);
      await tester.pump(const Duration(seconds: 61));
      expect(
          find.byKey(const Key('pinka-first-payment-review')), findsOneWidget);
      await h.finish(tester);
    });

    testWidgets('proslava samo jednom kroz received → minted → settled → paid',
        (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      final h = _SepaHarness();
      await h.start(tester);

      h.rail.stage = 'received_processing';
      await h.tick(tester);
      await tester.pump(const Duration(seconds: 1)); // animacija do kraja
      expect(h.haptics, 1);
      expect(_successIconScale(tester), closeTo(1, 0.001));

      h.rail.stage = 'minted';
      await h.tick(tester);
      expect(find.text(l.pinkaSepaMintedForwarding), findsOneWidget);
      // Ikona NIJE krenula ispočetka (tween bi počeo od 0,4).
      expect(_successIconScale(tester), closeTo(1, 0.001));

      h.rail.stage = 'settled';
      await h.tick(tester);
      expect(find.text(l.pinkaPaymentConfirmedOnchain), findsOneWidget);
      expect(_successIconScale(tester), closeTo(1, 0.001));
      final railCallsAtSettle = h.rail.calls;

      h.client.rpcState = 'paid';
      await h.tick(tester);
      expect(h.paidCalls, 1);
      expect(h.haptics, 1);
      expect(_successIconScale(tester), closeTo(1, 0.001));
      // settled je terminalan — rail polling je stao.
      await h.tick(tester);
      expect(h.rail.calls, railCallsAtSettle);
      await h.finish(tester);
    });

    testWidgets('rejected nakon prikazanog uspjeha zamijeni uspjeh porukom',
        (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      final h = _SepaHarness();
      await h.start(tester);

      h.rail.stage = 'received_processing';
      await h.tick(tester);
      expect(find.text(l.pinkaThanksForSupport), findsOneWidget);

      h.rail
        ..stage = 'rejected'
        ..reason = 'Uplata nije prošla provjeru';
      await h.tick(tester);

      expect(find.text(l.pinkaThanksForSupport), findsNothing);
      expect(find.text(l.pinkaIntentRejected), findsOneWidget);
      expect(
          find.text(l.pinkaIntentRejectedReason('Uplata nije prošla provjeru')),
          findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(h.paidCalls, 0);
      expect(h.haptics, 1);
      await h.finish(tester);
    });

    testWidgets('polling ne staje nakon 5 min (prva uplata s novog IBAN-a)',
        (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      final h = _SepaHarness();
      await h.start(tester);

      // 8 minuta bez zaprimanja — stari tok je nakon 100 × 3 s odustajao.
      for (var i = 0; i < 160; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      final railCalls = h.rail.calls;
      final rpcCalls = h.client.rpcCalls;
      expect(rpcCalls, greaterThan(100));
      expect(find.text(l.pinkaScanInBankApp), findsOneWidget);

      await h.tick(tester);
      expect(h.rail.calls, greaterThan(railCalls));
      expect(h.client.rpcCalls, greaterThan(rpcCalls));

      // Mint nakon sati i dalje stigne do korisnika.
      h.rail.stage = 'received_processing';
      await h.tick(tester);
      expect(find.text(l.pinkaThanksForSupport), findsOneWidget);
      h.client.rpcState = 'paid';
      await h.tick(tester);
      expect(h.paidCalls, 1);
      await h.finish(tester);
    });
  });

  testWidgets('review_expected: true ističe provjeru odmah, false je skriva',
      (tester) async {
    final l = await AppLocalizations.delegate.load(const Locale('hr'));
    final h = _SepaHarness();
    await h.start(tester);

    h.rail
      ..stage = 'received_processing'
      ..reviewExpected = true;
    await h.tick(tester);
    expect(find.byKey(const Key('pinka-first-payment-review')), findsOneWidget);

    h.rail.reviewExpected = false;
    await h.tick(tester);
    expect(find.text(l.pinkaSepaReceivedProcessing), findsOneWidget);
    expect(find.text(l.pinkaSepaFirstPaymentReview), findsNothing);
    await h.finish(tester);
  });

  group('parseIntentStatus', () {
    test('rejected_reason se čita iz status bloka', () {
      final s = parseIntentStatus({
        'status': {
          'stage': 'rejected',
          'rejected_reason': 'counterpart rejected',
          'steps': [
            {'key': 'payment', 'status': 'proven'},
            {'key': 'processing', 'status': 'failed'},
          ],
        },
      })!;
      expect(s.isRejected, isTrue);
      expect(s.rejectedReason, 'counterpart rejected');
      expect(s.steps, hasLength(2));
    });

    test('review_expected i seconds_in_stage', () {
      final s = parseIntentStatus({
        'status': {
          'stage': 'received_processing',
          'review_expected': true,
          'seconds_in_stage': 75,
        },
      })!;
      expect(s.reviewExpected, isTrue);
      expect(s.secondsInStage, 75);
      final n = parseIntentStatus({
        'status': {'stage': 'minted', 'review_expected': null},
      })!;
      expect(n.reviewExpected, isNull);
    });

    test('stageovi zaprimanja', () {
      PinkaIntentStatus st(String stage) =>
          parseIntentStatus({'status': {'stage': stage}})!;
      expect(st('awaiting_payment').isReceived, isFalse);
      expect(st('received_processing').isReceived, isTrue);
      expect(st('minted').isMinted, isTrue);
      expect(st('forwarding').isMinted, isTrue);
      expect(st('settled').isReceived, isTrue);
      expect(st('rejected').isReceived, isFalse);
      expect(st('expired').isReceived, isFalse);
      expect(parseIntentStatus({'stage': 'x'}), isNull);
    });
  });
}
