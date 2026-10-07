import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/sponsor_offer.dart';
import '../theme/app_theme.dart';

/// Vremenska traka trenutaka u izlogu: cijela epizoda, a na njoj svaki
/// trenutak u boji stanja. Slobodno = zlatno ([AppTheme.sponsoredAccent], ista
/// boja kojom se plaćeni oglas kasnije vidi na seek baru), zauzeto = puna
/// siva, „netko upravo plaća" = šrafirano sivo, nije u ponudi = prazno.
///
/// Tap na trenutak zove [onTap]; traka sama ne odlučuje što je kupljivo.
class SponsorTimelineBar extends StatelessWidget {
  final List<SponsorOffer> offers;

  /// Trajanje epizode; bez njega traka se proteže do kraja zadnjeg trenutka.
  final int? durationSeconds;
  final String? selectedSlotKey;
  final void Function(SponsorOffer offer)? onTap;
  final double height;

  const SponsorTimelineBar({
    super.key,
    required this.offers,
    this.durationSeconds,
    this.selectedSlotKey,
    this.onTap,
    this.height = 28,
  });

  int get _total {
    final last = offers.isEmpty ? 0 : offers.map((o) => o.end).reduce(_max);
    final d = durationSeconds ?? 0;
    return d > last ? d : (last > 0 ? last : 1);
  }

  static int _max(int a, int b) => a > b ? a : b;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final total = _total;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // Prvi layout zna doći s 0 px (animirani/kolabirani roditelj).
        if (!w.isFinite || w < 4) return SizedBox(height: height);
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              for (final o in offers)
                Positioned(
                  left: (o.start / total * w).clamp(0.0, w - 3),
                  // Najmanje 3 px da se kratak trenutak vidi, ali ne preko
                  // desnog ruba.
                  width: ((o.end - o.start) / total * w).clamp(
                    3.0,
                    (w - (o.start / total * w).clamp(0.0, w - 3)).clamp(3.0, w),
                  ),
                  top: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.5),
                    child: Tooltip(
                      message: sponsorStateLabel(o, l),
                      child: InkWell(
                        onTap: onTap == null ? null : () => onTap!(o),
                        child: _Segment(
                          offer: o,
                          selected: o.slotKey == selectedSlotKey,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  final SponsorOffer offer;
  final bool selected;

  const _Segment({required this.offer, required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.sponsoredAccent(theme.brightness);
    final taken = theme.colorScheme.outline;
    final (Color? fill, Color border) = switch (offer.state) {
      SponsorSlotState.free => (accent.withValues(alpha: 0.75), accent),
      SponsorSlotState.sold => (taken.withValues(alpha: 0.55), taken),
      SponsorSlotState.held => (taken.withValues(alpha: 0.25), taken),
      _ => (null, theme.colorScheme.outlineVariant),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: selected ? theme.colorScheme.onSurface : border,
          width: selected ? 2 : 1,
        ),
      ),
    );
  }
}

/// „Slobodno" / „Zauzeto do 6. 11. 2026." / … — dijele traka, kartica
/// trenutka i potvrda.
String sponsorStateLabel(SponsorOffer o, AppLocalizations l) =>
    switch (o.state) {
      SponsorSlotState.free => l.sponsorStateFree,
      SponsorSlotState.held => l.sponsorStateHeld,
      SponsorSlotState.sold =>
        o.liveUntil == null
            ? l.sponsorStateSold
            : l.sponsorStateSoldUntil(formatSponsorDate(o.liveUntil!)),
      _ => l.sponsorStateBlocked,
    };

String sponsorZoneLabel(SponsorZone z, AppLocalizations l) => switch (z) {
  SponsorZone.opening => l.sponsorZoneOtvaranje,
  SponsorZone.body => l.sponsorZoneTijelo,
  SponsorZone.closing => l.sponsorZoneZatvaranje,
  SponsorZone.other => '',
};

/// `6. 11. 2026.` — hrvatski zapis datuma (IHJJ), lokalno vrijeme. Isti
/// zapis i u engleskom sučelju je svjesna cijena: ugovor ne nosi locale, a
/// `intl` DateFormat ovdje bi bio jedini u aplikaciji (vidi TODO u CLAUDE.md).
String formatSponsorDate(DateTime d) {
  final t = d.toLocal();
  return '${t.day}. ${t.month}. ${t.year}.';
}

/// `14:05` — lokalno vrijeme isteka holda.
String formatSponsorTime(DateTime d) {
  final t = d.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(t.hour)}:${p(t.minute)}';
}
