/// Faza obrade epizode — kontrakt koji stoji iza svake oznake i poruke o
/// stanju („U redu čekanja", „Preuzimamo", „Prepisujemo", „Pišemo članak").
///
/// Tri stvarna oblika s produkcije (izmjereno 26.8.2026.) su ovdje fiksirani
/// kao slučajevi, jer su upravo oni pokazali da je jedna poruka „AI obrada nije
/// gotova" bila premalo: epizoda bez ijedne datoteke, epizoda s metapodacima
/// bez medije, i epizoda s gotovim videom bez ijednog AI artefakta izgledaju
/// korisniku isto, a nisu isto.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/l10n/app_localizations.dart';
import 'package:domovina_ai/models/channel_detail.dart' show VideoPipeline;
import 'package:domovina_ai/models/episode_status.dart';
import 'package:domovina_ai/widgets/episode_status_card.dart';

EpisodeStatus status({
  bool info = true,
  bool media = false,
  bool transcript = false,
  bool summary = false,
  bool article = false,
  bool magisterium = false,
}) =>
    EpisodeStatus.measured(
      hasInfo: info,
      hasMedia: media,
      hasTranscript: transcript,
      hasSummary: summary,
      hasArticle: article,
      hasMagisterium: magisterium,
    );

Widget harness(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('hr'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('faza iz izmjerenog stanja', () {
    test('UclibQB3SZM: nema ni info.json — u redu čekanja', () {
      expect(status(info: false).stage, EpisodeStage.queued);
    });

    test('ZYG_ksNDl3s: info + sličica, nema medije — preuzimanje', () {
      expect(status().stage, EpisodeStage.fetched);
    });

    test('DnzG2OvRflI: video na CDN-u, nijedan AI artefakt — prijepis slijedi',
        () {
      expect(status(media: true).stage, EpisodeStage.mediaReady);
    });

    test('prijepis bez članka — pišemo članak', () {
      expect(
        status(media: true, transcript: true).stage,
        EpisodeStage.transcribed,
      );
    });

    test('članak postoji — epizoda je objavljena', () {
      expect(
        status(media: true, transcript: true, summary: true, article: true)
            .stage,
        EpisodeStage.published,
      );
    });

    test('prijepis implicira preuzeti zvuk i kad probe medije padne', () {
      // Transcode zna kasniti za prijepisom; faza ne smije nazadovati na
      // „preuzimamo" samo zato što `video_h264.mp4` u tom trenutku nije tu.
      final s = status(media: false, transcript: true);
      expect(s.stage, EpisodeStage.transcribed);
      expect(s.steps[EpisodeStep.media], EpisodeStepState.done);
    });
  });

  group('koraci', () {
    test('prvi neispunjeni korak je aktivan, ostali čekaju', () {
      final s = status(media: true);
      expect(s.steps[EpisodeStep.fetch], EpisodeStepState.done);
      expect(s.steps[EpisodeStep.media], EpisodeStepState.done);
      expect(s.steps[EpisodeStep.transcript], EpisodeStepState.active);
      expect(s.steps[EpisodeStep.summary], EpisodeStepState.pending);
      expect(s.steps[EpisodeStep.article], EpisodeStepState.pending);
      expect(s.steps[EpisodeStep.magisterium], EpisodeStepState.pending);
    });

    test('svaki korak ima stanje — kartica nikad ne crta rupu', () {
      for (final s in [
        status(info: false),
        status(),
        status(media: true),
        status(media: true, transcript: true, summary: true, article: true),
      ]) {
        for (final step in EpisodeStep.values) {
          expect(s.steps[step], isNotNull, reason: '$step u fazi ${s.stage}');
        }
      }
    });

    test('najviše jedan korak je aktivan', () {
      final active = status(media: true, transcript: true)
          .steps
          .values
          .where((v) => v == EpisodeStepState.active)
          .length;
      expect(active, 1);
    });
  });

  group('vantage', () {
    test('izmjereno stanje je označeno kao izmjereno', () {
      expect(status().measured, isTrue);
    });

    test('listing vantage NIJE izmjeren — zastavice su producentova namjera',
        () {
      final s = EpisodeStatus.fromPipeline(const VideoPipeline(
        hasTranscript: false,
        hasDiarized: false,
        hasSummary: false,
        hasArticle: false,
        hasMagisterium: false,
      ));
      expect(s.measured, isFalse);
      // Listing ne zna nista o mediji; epizoda JEST u listingu pa je
      // preuzimanje gotovo, a sve dalje ceka.
      expect(s.stage, EpisodeStage.fetched);
      expect(s.steps[EpisodeStep.fetch], EpisodeStepState.done);
    });

    test('listing bez pipeline bloka ne puca', () {
      expect(EpisodeStatus.fromPipeline(null).stage, EpisodeStage.fetched);
    });

    test('gotova epizoda nema oznaku', () {
      final s = EpisodeStatus.fromPipeline(const VideoPipeline(
        hasTranscript: true,
        hasDiarized: true,
        hasSummary: true,
        hasArticle: true,
        hasMagisterium: true,
      ));
      expect(s.stage, EpisodeStage.published);
    });
  });

  group('vanjski izvor', () {
    test('bez medije kod nas UI mora ponuditi izvor', () {
      expect(status(info: false).needsExternalSource, isTrue);
      expect(status().needsExternalSource, isTrue);
    });

    test('s medijom kod nas se izvor NE nameće — imamo što pustiti', () {
      expect(status(media: true).needsExternalSource, isFalse);
      expect(
        status(media: true, transcript: true).needsExternalSource,
        isFalse,
      );
    });
  });

  group('kartica', () {
    testWidgets('svaka faza ima svoj naslov i punu listu koraka',
        (tester) async {
      for (final s in [
        status(info: false),
        status(),
        status(media: true),
        status(media: true, transcript: true),
      ]) {
        await tester.pumpWidget(harness(EpisodeStatusCard(status: s)));
        await tester.pump();

        final l = AppLocalizations.of(
          tester.element(find.byType(EpisodeStatusCard)),
        );
        expect(find.text(s.headline(l)), findsOneWidget);
        for (final step in EpisodeStep.values) {
          expect(find.text(episodeStepLabel(step, l)), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('bez medije se NE tvrdi da video svira', (tester) async {
      // Regresija: raniji tekst za video epizode glasio je „Prikazujemo samo
      // video…" i kad videa nigdje nije bilo (ZYG_ksNDl3s na produkciji).
      await tester.pumpWidget(harness(EpisodeStatusCard(status: status())));
      await tester.pump();

      final l = AppLocalizations.of(
        tester.element(find.byType(EpisodeStatusCard)),
      );
      expect(
        find.text(l.episodeStageMediaReadyBodyVideo),
        findsNothing,
      );
      expect(find.text(l.episodeStageFetchedBody), findsOneWidget);
    });
  });
}
