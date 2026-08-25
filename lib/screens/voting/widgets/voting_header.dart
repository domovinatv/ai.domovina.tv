/// Zaglavlje ekrana `/glasanje` — **pet zasebnih widgeta**, po jedan za svako
/// stanje iz `docs/plans/2026-08-08-glasanje-o-kanalima.md` §8.2.
///
/// Namjerno NISU if-ovi u jednom buildu: svako stanje ima drugi ton (poziv,
/// upozorenje, potvrda, tješenje) i drugi CTA, pa bi jedan build s pet grana
/// bio mjesto gdje se copy jednog stanja tiho procuri u drugo. Odabir stanja
/// radi čista funkcija [resolveVotingHeaderState], a [buildVotingHeader] je
/// jedini dispečer.
///
/// Stanja:
/// 1. [VotingHeaderGuest] — gost/neverificiran (ljestvica bez akcije).
/// 2. [VotingHeaderReady] — verificiran, nije glasao (loss aversion, §2.2).
/// 3. [VotingHeaderVoted] — verificiran, glasao (sažetak + „vrati se sutra").
/// 4. [VotingHeaderAtRisk] — niz visi, zastavica ga još brani.
/// 5. [VotingHeaderBroken] — niz je pukao (jednokratno, bez srama).
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/vote_round.dart';
import '../../../models/voting_state.dart';
import '../../../theme/app_theme.dart';
import 'streak_flags.dart';

/// Stanje zaglavlja iz §8.2.
enum VotingHeaderState { guest, ready, voted, atRisk, broken }

/// Izbor stanja — čista funkcija (bez konteksta) da se da testirati i da se
/// pravilo ne razmaže po buildu.
///
/// [brokenDismissed] je jedini lokalni (ne-serverski) ulaz: ekran „niz je
/// pukao" je **jednokratan**, pa ga tap na CTA gasi do sljedećeg učitavanja.
VotingHeaderState resolveVotingHeaderState({
  required VotingState? state,
  StreakDisplay? display,
  bool brokenDismissed = false,
}) {
  if (state == null || !state.verified) return VotingHeaderState.guest;
  if (state.votedToday) return VotingHeaderState.voted;
  if (!brokenDismissed && (display?.streakBroken ?? false)) {
    return VotingHeaderState.broken;
  }
  // Server je autoritet za `streak_at_risk`; lokalna projekcija ga samo
  // pomiče naprijed kad je ekran ostao otvoren preko ponoći (§6.3).
  final ugrozen = display?.streakAtRisk ?? state.streakAtRisk;
  if (ugrozen) return VotingHeaderState.atRisk;
  return VotingHeaderState.ready;
}

/// Dispečer — jedino mjesto koje zna preslikavanje stanje → widget.
Widget buildVotingHeader({
  required VotingHeaderState stanje,
  required VotingState? state,
  required VoteRound? round,
  required DateTime? today,
  StreakDisplay? display,
  String? todayCandidateName,
  VoidCallback? onBrokenDismiss,
}) {
  switch (stanje) {
    case VotingHeaderState.guest:
      return VotingHeaderGuest(round: round, today: today);
    case VotingHeaderState.ready:
      return VotingHeaderReady(
        state: state!,
        round: round,
        today: today,
        prikazniNiz: display?.displayedStreak ?? state.streak,
      );
    case VotingHeaderState.voted:
      return VotingHeaderVoted(
        state: state!,
        round: round,
        today: today,
        kandidat: todayCandidateName,
      );
    case VotingHeaderState.atRisk:
      return VotingHeaderAtRisk(
        state: state!,
        round: round,
        today: today,
        display: display,
      );
    case VotingHeaderState.broken:
      return VotingHeaderBroken(
        state: state!,
        round: round,
        today: today,
        onStart: onBrokenDismiss,
      );
  }
}

/// `8.8.2026.` — namjerno brojčano.
///
/// Ime dana i mjeseca bi tražilo `intl` `DateFormat` s locale podacima; isti
/// dug već stoji u `founder_booking.dart` (CLAUDE.md TODO). Brojčani zapis je
/// ispravan u oba jezika i ne uvodi ručne hrvatske nazive mjeseci.
String formatElectionDay(DateTime day) => '${day.day}.${day.month}.${day.year}.';

// ---------------------------------------------------------------------------
// Zajednička ljuska
// ---------------------------------------------------------------------------

class _HeaderShell extends StatelessWidget {
  final List<Widget> children;

  /// Naglašena (crvenkasta) varijanta — samo stanja 4 i 5.
  final bool alarm;

  const _HeaderShell({required this.children, this.alarm = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: alarm
            ? AppTheme.croRed.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: alarm
                ? AppTheme.croRed.withValues(alpha: 0.35)
                : cs.outlineVariant,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// „Izborni dan · 8.8.2026." + „Kolo 7 · još 6 dana".
class _DayAndRoundLine extends StatelessWidget {
  final VoteRound? round;
  final DateTime? today;

  const _DayAndRoundLine({required this.round, required this.today});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final cs = theme.colorScheme;

    final dijelovi = <String>[
      // `votingElectionDayPlain`, NE `votingTitle`: ovaj redak nosi PROZOR
      // glasanja (ponoć–ponoć, Europe/Zagreb), a `votingTitle` je od 25.8.2026.
      // oznaka feature-a („Tko ide sljedeći").
      today == null
          ? l.votingElectionDayPlain
          : l.votingElectionDay(formatElectionDay(today!)),
      if (round != null) l.votingRoundLabel(round!.id),
      if (round != null) _preostalo(l),
    ].where((e) => e.isNotEmpty).toList(growable: false);

    return Text(
      dijelovi.join(' · '),
      style: theme.textTheme.labelSmall?.copyWith(
        color: cs.onSurfaceVariant,
        letterSpacing: 0.6,
      ),
    );
  }

  String _preostalo(AppLocalizations l) {
    final r = round!;
    final preostalo = today != null ? r.daysLeftOn(today!) : (r.daysLeft ?? 0);
    if (preostalo < 0) return '';
    if (preostalo == 0) return l.votingRoundLastDay;
    return l.votingRoundDaysLeft(preostalo);
  }
}

/// Niz + zastavice u jednom redu (stanja 2–4).
class _StreakLine extends StatelessWidget {
  final int niz;
  final int zastavice;
  final bool ugrozen;

  const _StreakLine({
    required this.niz,
    required this.zastavice,
    this.ugrozen = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StreakBadge(dani: niz, ugrozen: ugrozen),
        const SizedBox(width: 10),
        StreakFlags(imaZastavica: zastavice),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Gost / neverificiran
// ---------------------------------------------------------------------------

/// Ljestvica je javna — glasati može samo potvrđeni građanin.
///
/// U ovom krugu **nema** akcijskog gumba na karticama (`⚑ Prati` iz §8.2 dolazi
/// s `candidate_follows` UI-jem, koji je Van opsega); poziv na potvrdu nosi
/// trajna traka [VotingVerifyBar] na dnu ekrana.
class VotingHeaderGuest extends StatelessWidget {
  final VoteRound? round;
  final DateTime? today;

  const VotingHeaderGuest({super.key, this.round, this.today});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return _HeaderShell(
      children: [
        _DayAndRoundLine(round: round, today: today),
        const SizedBox(height: 6),
        Text(
          l.votingGuestTitle,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          l.votingGuestBody,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (round?.totalVotes != null) ...[
          const SizedBox(height: 6),
          _RoundTotals(round: round!),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Verificiran, nije glasao
// ---------------------------------------------------------------------------

/// Aktivno stanje: „Imaš 1 glas." + loss aversion nad postojećim nizom (§2.2).
class VotingHeaderReady extends StatelessWidget {
  final VotingState state;
  final VoteRound? round;
  final DateTime? today;
  final int prikazniNiz;

  const VotingHeaderReady({
    super.key,
    required this.state,
    required this.prikazniNiz,
    this.round,
    this.today,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return _HeaderShell(
      children: [
        _DayAndRoundLine(round: round, today: today),
        const SizedBox(height: 6),
        _StreakLine(niz: prikazniNiz, zastavice: state.flags),
        const SizedBox(height: 8),
        Text(
          l.votingHaveVote,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (prikazniNiz > 0) ...[
          const SizedBox(height: 2),
          Text(
            l.votingLossAversion(prikazniNiz),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Verificiran, glasao
// ---------------------------------------------------------------------------

/// Sažetak današnjeg glasa + „vrati se sutra". Lista ide u read-only stanje.
class VotingHeaderVoted extends StatelessWidget {
  final VotingState state;
  final VoteRound? round;
  final DateTime? today;

  /// Naziv kandidata na kojeg je glas otišao; `null` dok ljestvica nije stigla
  /// (tada se prikazuje samo slug-neovisna potvrda).
  final String? kandidat;

  const VotingHeaderVoted({
    super.key,
    required this.state,
    this.round,
    this.today,
    this.kandidat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final glas = state.todayVote;

    return _HeaderShell(
      children: [
        _DayAndRoundLine(round: round, today: today),
        const SizedBox(height: 6),
        _StreakLine(niz: state.streak, zastavice: state.flags),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: AppTheme.croBlue),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l.votingVotedToday,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        if (glas != null && kandidat != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                glas.isUp ? Icons.thumb_up : Icons.thumb_down,
                size: 14,
                color: glas.isUp ? AppTheme.croBlue : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  kandidat!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 2),
        Text(
          l.votingComeBackTomorrow,
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Niz visi
// ---------------------------------------------------------------------------

/// Zadnji dan u kojem zastavice još mogu obraniti niz (§6.3).
class VotingHeaderAtRisk extends StatelessWidget {
  final VotingState state;
  final VoteRound? round;
  final DateTime? today;
  final StreakDisplay? display;

  const VotingHeaderAtRisk({
    super.key,
    required this.state,
    this.round,
    this.today,
    this.display,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final niz = display?.displayedStreak ?? state.streak;
    final izgorjet = display?.flagsThatWillBurn ?? state.flagsThatWillBurn;

    return _HeaderShell(
      alarm: true,
      children: [
        _DayAndRoundLine(round: round, today: today),
        const SizedBox(height: 6),
        _StreakLine(niz: niz, zastavice: state.flags, ugrozen: true),
        const SizedBox(height: 8),
        Text(
          l.votingAtRiskTitle(niz),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.croRed,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          izgorjet > 0 ? l.votingAtRiskBurn(izgorjet) : l.votingAtRiskBody,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Niz je pukao
// ---------------------------------------------------------------------------

/// Jednokratna poruka bez srama — niz je stao, najduži ostaje, kreni ispočetka.
class VotingHeaderBroken extends StatelessWidget {
  final VotingState state;
  final VoteRound? round;
  final DateTime? today;

  /// Zatvara jednokratni prikaz i vraća ekran u stanje 2 (aktivno glasanje).
  final VoidCallback? onStart;

  const VotingHeaderBroken({
    super.key,
    required this.state,
    this.round,
    this.today,
    this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return _HeaderShell(
      alarm: true,
      children: [
        _DayAndRoundLine(round: round, today: today),
        const SizedBox(height: 8),
        Text(
          // `my_voting_state().streak` je **prikazni** niz — kad je pukao, server
          // ga već vraća kao 0 i broj prije pucanja nigdje ne postoji u ugovoru
          // (§6.3). Broj se zato navodi samo kad ga stvarno znamo (stanje iz
          // lokalnog cachea, gdje je zapisan predpucanjski niz).
          state.streak > 0
              ? l.votingBrokenTitle(state.streak)
              : l.votingBrokenTitleUnknown,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.croRed,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l.votingBrokenLongest(state.longestStreak),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: onStart,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.croBlue,
            foregroundColor: Colors.white,
            side: AppTheme.brandRim(theme.brightness),
          ),
          child: Text(l.votingBrokenCta),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Transparentnost kola + trajna traka za neverificirane
// ---------------------------------------------------------------------------

/// „142 glasa · 87 glasača" — agregat kola (§4.2: objavljujemo samo zbrojeve).
class _RoundTotals extends StatelessWidget {
  final VoteRound round;

  const _RoundTotals({required this.round});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final dijelovi = <String>[
      if (round.totalVotes != null) l.votingRoundVotes(round.totalVotes!),
      if (round.voters != null) l.votingRoundVoters(round.voters!),
    ];
    if (dijelovi.isEmpty) return const SizedBox.shrink();
    return Text(
      dijelovi.join(' · '),
      style: theme.textTheme.labelSmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// Trajna traka „Potvrdi se e-Osobnom i glasaj".
///
/// Trajna površina, ne modal — CLAUDE.md pravilo o nudge-evima (modal samo kad
/// ga korisnik svojim tapom pozove). Ista mehanika kao `AnonymousSignInBar`.
class VotingVerifyBar extends StatelessWidget {
  final VoidCallback onVerify;

  /// Traka je najniži element ekrana → sama respektira donji notch/gestu.
  final bool applyBottomSafeArea;

  const VotingVerifyBar({
    super.key,
    required this.onVerify,
    this.applyBottomSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 420;

    return Material(
      color: cs.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        bottom: applyBottomSafeArea,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: InkWell(
            onTap: onVerify,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.badge_outlined, color: AppTheme.croRed, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.votingVerifyBarTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (!narrow)
                          Text(
                            l.votingVerifyBarBody,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Brand navy fill + rim (nikad cs.primary — M3 ga u dark temi
                  // izblijedi pa bijeli tekst izgleda isprano).
                  FilledButton(
                    onPressed: onVerify,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.croBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      side: AppTheme.brandRim(theme.brightness),
                    ),
                    child: Text(l.votingVerifyCta),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
