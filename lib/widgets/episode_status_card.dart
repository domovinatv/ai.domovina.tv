import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/episode_status.dart';

/// Kartica koja korisniku objasni u kojem je točno stanju epizoda koja još
/// nije prošla cijelu obradu.
///
/// Zamjenjuje raniju jednu poruku „AI obrada još nije gotova", koja je za sva
/// nedovršena stanja tvrdila isto — a stanja su bitno različita i različito
/// utječu na to što korisnik uopće može učiniti (vidi [EpisodeStage]).
/// Najgore je bilo što je tekst za video epizode glasio „Prikazujemo samo
/// video…" i kad videa nije bilo nigdje.
///
/// Lista koraka je namjerno u korisnikovu rječniku („Prijepis govora"), ne u
/// imenima datoteka — nazivi artefakata su naša implementacija.
class EpisodeStatusCard extends StatelessWidget {
  final EpisodeStatus status;

  /// Mijenja tekst za fazu [EpisodeStage.mediaReady] („gledaj" vs „slušaj").
  final bool audioOnly;

  /// Dodatni redak ispod objašnjenja — npr. „Epizoda … nije pronađena na
  /// CDN-u." za fazu čekanja, gdje je korisno vidjeti i identifikator.
  final String? footnote;

  const EpisodeStatusCard({
    super.key,
    required this.status,
    this.audioOnly = false,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withAlpha(140),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.tertiary.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                status.stage == EpisodeStage.queued
                    ? Icons.schedule_outlined
                    : Icons.auto_awesome_outlined,
                size: 20,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.headline(l),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status.body(l, audioOnly: audioOnly),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        height: 1.4,
                      ),
                    ),
                    if (footnote != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        footnote!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onTertiaryContainer
                              .withAlpha(170),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            l.episodeStatusStepsTitle,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: theme.colorScheme.onTertiaryContainer.withAlpha(200),
            ),
          ),
          const SizedBox(height: 8),
          ...EpisodeStep.values.map(
            (step) => _StepRow(
              label: episodeStepLabel(step, l),
              state: status.steps[step] ?? EpisodeStepState.pending,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final EpisodeStepState state;

  const _StepRow({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.onTertiaryContainer;

    // Boje/ikone nose isto značenje kao u loading ekranu epizode: zelena
    // kvačica = gotovo, prsten = na redu, prigušena crtica = čeka.
    final (IconData icon, Color color, double alpha) = switch (state) {
      EpisodeStepState.done => (Icons.check_circle, const Color(0xFF2E7D32), 1.0),
      EpisodeStepState.active => (Icons.radio_button_checked, base, 1.0),
      EpisodeStepState.pending => (Icons.remove, base, 0.45),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color.withValues(alpha: alpha)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: base.withValues(alpha: alpha),
                fontWeight: state == EpisodeStepState.active
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
