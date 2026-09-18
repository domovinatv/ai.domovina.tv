/// Prikaz niza (🔥) i zastavica u zaglavlju glasanja.
///
/// Plan: `docs/plans/2026-08-08-glasanje-o-kanalima.md` §6.1, §8.2.
///
/// Zastavica je [HrvatskaZastavica] (`CustomPaint`) — nikad emoji: 🇭🇷 se ne
/// renderira na Windows Chromeu. Niz koristi `Icons.local_fire_department` iz
/// istog razloga (emoji 🔥 ima platformske rupe u prikazu).
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/voting_state.dart' show kMaxVoteFlags;
import '../../../theme/app_theme.dart';
import '../../../widgets/hrvatska_zastavica.dart';

/// „Niz od 12 dana" + plamen. Bez niza (0) prikazuje poziv, ne nulu.
class StreakBadge extends StatelessWidget {
  final int dani;

  /// Niz visi (§8.2 stanje 4) — plamen prelazi u brand crvenu.
  final bool ugrozen;

  const StreakBadge({super.key, required this.dani, this.ugrozen = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final boja = ugrozen ? AppTheme.croRed : theme.colorScheme.onSurface;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          dani > 0 ? Icons.local_fire_department : Icons.mode_standby,
          size: 18,
          color: dani > 0 ? boja : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          dani > 0 ? l.votingStreakDays(dani) : l.votingStreakNone,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: dani > 0 ? boja : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Red zastavica: [imaZastavica] ispunjenih + ostatak do [maksimum] praznih.
///
/// Trošenje zastavice animira `AnimatedSwitcher` (v1 iz §8.3 — Rive je bio
/// alternativa, nije potreban): red se prekriži na novi broj s kratkim
/// fade+scale prijelazom, pa se „potrošena" zastavica vidi kako nestaje.
class StreakFlags extends StatelessWidget {
  final int imaZastavica;
  final int maksimum;
  final double visina;

  const StreakFlags({
    super.key,
    required this.imaZastavica,
    this.maksimum = kMaxVoteFlags,
    this.visina = 14,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final broj = imaZastavica.clamp(0, maksimum);

    return Tooltip(
      message: l.votingFlagsTooltip,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        ),
        child: Row(
          key: ValueKey<int>(broj),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < maksimum; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              HrvatskaZastavica(
                visina: visina,
                ispunjena: i < broj,
                semantickiOpis: i == 0 ? l.votingFlagsLeft(broj) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
