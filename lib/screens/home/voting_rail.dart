import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../models/vote_candidate.dart';
import '../../services/voting_service.dart';
import '../../theme/app_theme.dart';
import '../voting/widgets/candidate_tile.dart' show CandidateAvatar;
import 'episodes_rail.dart';

/// Home rail „Izborni dan" — vrh ljestvice kandidata, javno.
///
/// Plan: `docs/plans/2026-08-08-glasanje-o-kanalima.md` §8.6 (jedina od četiri
/// ulazne točke koja u krugu 8.8.2026. nije isporučena).
///
/// **Vidljiv je svima, uključujući gosta i korisnika prijavljenog Googleom.**
/// To je namjerno i ispravlja izvornu grešku: glasanje je bilo dostupno samo
/// s `/channels` trake, pa korisnik koji nije potvrđen e-Osobnom nikad nije ni
/// doznao da sustav postoji — a upravo njega treba dovesti do Certilije.
/// Ljestvica je javna po RLS-u (`round_leaderboard` je `anon` RPC), pa rail ne
/// traži sesiju i ne zove nijedan autentificirani RPC.
///
/// Widget je **samodostatan** kao `PersonsRail`: sam dohvaća, sam se sakrije
/// kad kola nema, kad je ljestvica prazna ili kad RPC padne — home tada izgleda
/// točno kao prije.
class VotingRail extends StatefulWidget {
  final bool isMobile;

  /// Koliko kandidata ide u traku. Deseti je gornja granica čitljivosti —
  /// rail je pregled, puni popis (181 kandidat) živi na `/glasanje`.
  final int limit;

  const VotingRail({super.key, required this.isMobile, this.limit = 10});

  @override
  State<VotingRail> createState() => _VotingRailState();
}

class _VotingRailState extends State<VotingRail> {
  final VotingService _service = VotingService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    // Dohvat IZVAN build faze: `ensurePreviewLoaded` na već dovršenom Futureu
    // notifira sinkrono, a iz initState/build-a bi to srušilo frame drugim
    // slušateljima servisa (ista zamka kao u PersonsRail-u).
    unawaited(Future.microtask(
      () => _service.ensurePreviewLoaded(limit: widget.limit),
    ));
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final kandidati = _service.previewCandidates;
    if (kandidati.isEmpty) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    final width = widget.isMobile ? 140.0 : 160.0;

    return Semantics(
      identifier: 'home-voting-rail',
      container: true,
      child: EpisodesRail(
        eyebrow: l.votingTitle,
        // Brand crvena kao naglasak trake — izborni dan je jedina hrvatska
        // površina u aplikaciji koja nosi zastavice.
        eyebrowAccentColor: AppTheme.croRed,
        isMobile: widget.isMobile,
        onSeeAll: () => context.go('/glasanje'),
        seeAllLabel: l.votingRailSeeAll,
        cards: [
          for (final c in kandidati.take(widget.limit))
            _VotingRailTile(
              candidate: c,
              width: width,
              // Deep-link na kandidata: `/glasanje/:slug` otvara detalj sheet.
              // Slug ide DOSLOVNO (CLAUDE.md / person hub pravilo).
              onTap: () => context.go('/glasanje/${c.slug}'),
            ),
          _VotingRailCta(width: width, onTap: () => context.go('/glasanje')),
        ],
      ),
    );
  }
}

/// Uska kartica kandidata — avatar, ime, mjesto na ljestvici i neto rezultat.
///
/// Tiša je od `CandidateTile` s `/glasanje`: rail nema gumbe za glasanje jer bi
/// tap na 👍 gosta doveo do `not_verified` greške bez konteksta. Ovdje se samo
/// pokazuje da natjecanje postoji; glasanje se događa na ekranu koji uz sebe
/// ima i traku za potvrdu e-Osobnom.
class _VotingRailTile extends StatelessWidget {
  final VoteCandidate candidate;
  final double width;
  final VoidCallback onTap;

  const _VotingRailTile({
    required this.candidate,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final net = candidate.net;
    // Pozitivan neto ide u `cs.primary`, NE u `AppTheme.croBlue`: pravilo
    // „navy = croBlue" vrijedi za POVRŠINE koje se boje (fill + rim), a #002F6C
    // kao 11 dp tekst na tamnoj podlozi je nečitljiv. `cs.primary` je izveden
    // iz istog brand sjemena, pa je u svijetloj temi ta ista navy, a u tamnoj
    // njezina svijetla varijanta.
    final bojaNeto = net > 0
        ? theme.colorScheme.primary
        : (net < 0 ? AppTheme.croRed : theme.colorScheme.onSurfaceVariant);

    return Semantics(
      identifier: 'voting-rail-card-${candidate.slug}',
      container: true,
      child: SizedBox(
        width: width,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CandidateAvatar(candidate: candidate, size: width),
                const SizedBox(height: 8),
                Text(
                  candidate.displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (candidate.rank != null) ...[
                      Flexible(
                        child: Text(
                          l.votingRailRank(candidate.rank!),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      net > 0 ? '+$net' : '$net',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: bojaNeto,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Zadnja kartica trake — objašnjenje što rail zapravo je + ulaz na `/glasanje`.
///
/// Nosi je jer je rail za većinu korisnika PRVI susret s glasanjem: same
/// sličice kandidata ne kažu ni da se glasa, ni tko smije. Kartica je trajna
/// površina, ne modal (CLAUDE.md pravilo o nudge-evima).
class _VotingRailCta extends StatelessWidget {
  final double width;
  final VoidCallback onTap;

  const _VotingRailCta({required this.width, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: width,
                height: width,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // Brand navy fill + rim, nikad cs.primary (M3 ga u dark temi
                  // izblijedi pa bijeli sadržaj izgleda isprano).
                  color: AppTheme.croBlue,
                  borderRadius: BorderRadius.circular(width / 4),
                  border: Border.fromBorderSide(
                    AppTheme.brandRim(theme.brightness),
                  ),
                ),
                child: Icon(
                  Icons.how_to_vote_outlined,
                  size: width * 0.4,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.votingRailCtaTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                l.votingRailCtaBody,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
