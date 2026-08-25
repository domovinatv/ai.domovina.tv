import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/voting_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/typography.dart';
import '../../widgets/account_chip.dart';
import '../../widgets/language_toggle_button.dart';
import '../../widgets/theme_toggle_button.dart';
import '../../l10n/app_localizations.dart';
import '../voting/widgets/streak_flags.dart';

/// Slim sticky app bar za home screen.
///
/// Layout:
/// [Logo "DOMOVINA.ai"]  [Pretraži ⌘K placeholder]  [AccountChip]
///
/// Search trigger je placeholder za sada — modal overlay dolazi u Korak 9.
/// Klik vodi na isti search field u headeru ispod (scroll + focus).
class HomeAppBar extends StatelessWidget {
  /// Callback kad user klikne na search trigger. Privremeno scrolla na
  /// postojeći search input u headeru; kasnije će otvoriti search overlay.
  final VoidCallback? onSearchTap;

  const HomeAppBar({super.key, this.onSearchTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l = AppLocalizations.of(context);

    return SliverAppBar(
      pinned: true,
      floating: false,
      snap: false,
      toolbarHeight: 64,
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0.5,
      elevation: 0,
      automaticallyImplyLeading: false,
      // titleSpacing mora biti 0: rubni razmak živi kao content padding
      // UNUTAR scrollabilnog reda, inače se scroll sadržaj reže 16px od
      // ruba ekrana umjesto da klizi do njega.
      titleSpacing: 0,
      title: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          if (isMobile) {
            // Uski mobiteli: sve akcije stanu rijetko kad — red je zato
            // horizontalno scrollabilan (desni kraj s Prijava gumbom se
            // doscrolla umjesto da bude odrezan).
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Wordmark(isDark: isDark),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.search, size: 20),
                    tooltip: l.homeSearchTooltip,
                    onPressed: onSearchTap,
                  ),
                  const SizedBox(width: 4),
                  const VotingStreakChip(),
                  const SizedBox(width: 4),
                  const LanguageToggleButton(),
                  const SizedBox(width: 4),
                  const ThemeToggleButton(),
                  const SizedBox(width: 4),
                  const AccountChip(),
                ],
              ),
            );
          }
          return Padding(
            // Desktop red nije scrollabilan pa je vanjski padding ovdje OK —
            // vizualno identično starom titleSpacing: 16.
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _Wordmark(isDark: isDark),
                const SizedBox(width: 24),
                Expanded(
                  child: _SearchTrigger(
                    onTap: onSearchTap,
                    placeholder: l.homeSearchPlaceholderFull,
                  ),
                ),
                const SizedBox(width: 16),
                const VotingStreakChip(),
                const SizedBox(width: 4),
                const LanguageToggleButton(),
                const SizedBox(width: 4),
                const ThemeToggleButton(),
                const SizedBox(width: 4),
                const AccountChip(),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Chip s nizom („Izborni dan") u home zaglavlju — trajna ulazna točka na
/// `/glasanje`.
///
/// Plan: `docs/plans/2026-08-08-glasanje-o-kanalima.md` §8.6.
///
/// **Niz i zastavice vidi samo verificirani građanin** — postoje isključivo za
/// korisnika potvrđenog e-Osobnom (odluka 3 iz predaje). Svi ostali dobiju
/// [_VotingDiscoverChip]: isti položaj, ista ruta, bez brojke koja im ništa ne
/// znači.
///
/// Do 25.8.2026. je chip za neverificirane vraćao `SizedBox.shrink()`, uz
/// obrazloženje da bi im ovdje stajao prazan simbol. To je bila greška: gost i
/// korisnik prijavljen Googleom time nisu imali NIJEDAN znak da glasanje
/// postoji (jedini javni ulaz bio je traka na dnu `/channels`), pa se nisu
/// imali zašto potvrditi e-Osobnom. Odluka 3 gate-a **glas**, ne saznanje da se
/// glasa.
///
/// Crvena točka = današnji glas još nije potrošen. Nikakav modal ni snackbar —
/// CLAUDE.md pravilo o nudge-evima traži trajnu površinu.
///
/// Vizual je namjerno kompaktniji od [StreakBadge]a s ekrana glasanja (plamen +
/// broj umjesto „Niz 12 dana"): ovaj red na mobitelu već nosi četiri akcije, a
/// puna rečenica bi ga odgurala izvan vidljivog dijela scrollabla. Zastavice su
/// isti [StreakFlags] widget.
class VotingStreakChip extends StatefulWidget {
  const VotingStreakChip({super.key});

  @override
  State<VotingStreakChip> createState() => _VotingStreakChipState();
}

class _VotingStreakChipState extends State<VotingStreakChip> {
  final VotingService _service = VotingService.instance;

  /// Dohvat je zatražen — sprječava ponovni RPC na svaku notifikaciju servisa.
  bool _zatrazeno = false;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onChanged);
    _service.addListener(_onChanged);
    _mozdaUcitaj();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onChanged);
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // Prijava/verifikacija može stići nakon što je chip već u stablu.
    _mozdaUcitaj();
    setState(() {});
  }

  /// `refresh(withLeaderboard: false)`, **ne** `ensureLoaded()`: potonji uz
  /// stanje povuče i cijelu ljestvicu (181 kandidat) koju chip ne prikazuje.
  ///
  /// Poziv ide kroz microtask jer `refresh` na pogodak lokalnog cachea okine
  /// `notifyListeners()` sinkrono — iz `initState`/`build` faze bi to srušilo
  /// frame drugim slušateljima servisa.
  void _mozdaUcitaj() {
    if (_zatrazeno || !_verificiran) return;
    _zatrazeno = true;
    unawaited(Future.microtask(() => _service.refresh(withLeaderboard: false)));
  }

  bool get _verificiran => AuthService.instance.currentUser?.isVerified ?? false;

  @override
  Widget build(BuildContext context) {
    if (!_verificiran) return const _VotingDiscoverChip();

    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final display = _service.displayFor();
    // Prikazani niz je projekcija za današnji dan (niz koji je pukao je 0), a
    // ne sirovi `streak` iz baze — isti broj koji stoji u zaglavlju glasanja.
    final niz = display?.displayedStreak ?? _service.state?.streak ?? 0;
    final zastavice = _service.state?.flags ?? 0;
    final ugrozen = display?.streakAtRisk ?? false;
    final neiskoristen = _service.hasUnusedVote;
    final boja = ugrozen ? AppTheme.croRed : theme.colorScheme.onSurface;

    return Tooltip(
      message: neiskoristen ? l.votingUnusedVote : l.votingHomeChipTooltip,
      child: Semantics(
        button: true,
        label: neiskoristen
            ? '${l.votingTitle} · ${l.votingUnusedVote}'
            : l.votingTitle,
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => context.go('/glasanje'),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          niz > 0
                              ? Icons.local_fire_department
                              : Icons.how_to_vote_outlined,
                          size: 16,
                          color: niz > 0
                              ? boja
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        if (niz > 0) ...[
                          const SizedBox(width: 3),
                          Text(
                            '$niz',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: boja,
                            ),
                          ),
                        ],
                        if (zastavice > 0) ...[
                          const SizedBox(width: 6),
                          StreakFlags(imaZastavica: zastavice, visina: 9),
                        ],
                      ],
                    ),
                  ),
                  if (neiskoristen)
                    Positioned(
                      top: -1,
                      right: -1,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppTheme.croRed,
                          shape: BoxShape.circle,
                          // Prsten u boji podloge — točka mora čitati i kad
                          // padne preko obruba chipa.
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                      ),
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

/// Chip „Izborni dan" za korisnika BEZ potvrde e-Osobnom (gost, Google, Apple…).
///
/// Isto mjesto i ista ruta kao [VotingStreakChip], ali bez niza, zastavica i
/// crvene točke — sve troje su podaci verificiranog glasača. Ovdje stoji samo
/// znak da natjecanje postoji; objašnjenje i poziv na potvrdu čekaju na
/// `/glasanje` (`VotingVerifyBar`), gdje uz sebe imaju i ljestvicu.
///
/// **Ne dira nijedan RPC.** Svojstvo „neverificirani ne okidaju `my_voting_state`"
/// iz T5 ostaje netaknuto — chip je čisti navigacijski element.
///
/// Natpis se pojavi tek od **840 dp**, ne od desktop praga (600 dp). Razlog je
/// izmjeren: na 606 dp logičke širine desktop red zaglavlja s natpisom pukne
/// („BOTTOM OVERFLOWED BY 38 PIXELS") jer `Expanded` oko `_SearchTrigger`a
/// spadne ispod ~90 dp koliko traži njegov vlastiti sadržaj (ikona + ⌘K
/// značka). Ikona bez natpisa uzima ~40 dp umjesto ~103 dp i red diše.
/// Na mobitelu (< 600 dp) red se ionako horizontalno scrolla, pa bi natpis
/// samo odgurao `AccountChip` — jedini ulaz u prijavu — izvan vidljivog dijela.
/// Tooltip i Semantics nose značenje na svim širinama.
class _VotingDiscoverChip extends StatelessWidget {
  const _VotingDiscoverChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final sirok = MediaQuery.sizeOf(context).width >= 840;

    return Tooltip(
      message: l.votingHomeChipTooltip,
      child: Semantics(
        button: true,
        label: l.votingTitle,
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => context.go('/glasanje'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand crvena, ne onSurfaceVariant: chip mora odskočiti od
                    // reda sivih ikona (pretraga, jezik, tema) da ga oko uopće
                    // primijeti — to je jedina svrha ove površine.
                    Icon(
                      Icons.how_to_vote_outlined,
                      size: 16,
                      color: AppTheme.croRed,
                    ),
                    if (sirok) ...[
                      const SizedBox(width: 5),
                      Text(
                        l.votingTitle,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wordmark "DOMOVINA.ai" — Playfair serif za premium editorial vibe.
/// `.ai` sufiks je u croRed kao Croatian flag akcent.
class _Wordmark extends StatelessWidget {
  final bool isDark;

  const _Wordmark({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final baseColor = isDark
        ? Colors.white
        : Theme.of(context).colorScheme.primary;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'DOMOVINA',
            style: AppTypography.wordmarkStyle(color: baseColor, fontSize: 22),
          ),
          TextSpan(
            text: '.ai',
            style: AppTypography.wordmarkStyle(
              color: Theme.of(context).colorScheme.tertiary,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}

/// Search trigger button — izgleda kao input field, ali otvara overlay.
class _SearchTrigger extends StatelessWidget {
  final VoidCallback? onTap;
  final String placeholder;

  const _SearchTrigger({required this.onTap, required this.placeholder});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 40,
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: theme.colorScheme.surfaceContainerLow,
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  placeholder,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.7,
                    ),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // ⌘K placeholder hint — funkcionira tek u Korak 9.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '⌘K',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
