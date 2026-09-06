/// „Izborni dan" — ekran `/glasanje`.
///
/// Plan: `docs/plans/2026-08-08-glasanje-o-kanalima.md` §8; predaja
/// `2026-08-08-glasanje-predaja.md` (ugovor v1.1 + ispravci).
///
/// Ljestvica kola je **javna** (gost je vidi cijelu), glasanje nije: jedan glas
/// svakih 24 h ima samo građanin potvrđen e-Osobnom. U ovom krugu gost NEMA
/// akcijski gumb na kartici (`⚑ Prati` čeka `candidate_follows` UI) — poziv na
/// potvrdu nosi trajna traka [VotingVerifyBar] na dnu (CLAUDE.md: nudge je
/// trajna površina, nikad modal preko sadržaja).
///
/// Sortiranje i pretraga idu **na server** (`round_leaderboard(p_sort, p_tag,
/// p_query)`) — s 181 kandidatom i `random` / `least_votes` redoslijedom koje
/// zna samo baza, lokalno presortiravanje bi lagalo o rangu.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart' show log;
import '../../models/vote_candidate.dart';
import '../../models/vote_round.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart' show appStrings;
import '../../services/voting_service.dart';
import '../../theme/app_theme.dart';
import 'widgets/candidate_tile.dart';
import 'widgets/voting_header.dart';
import '../../router/nav.dart';

class VotingScreen extends StatefulWidget {
  /// `/glasanje/:slug` — deep-link koji nakon učitavanja otvori detalj
  /// kandidata preko ljestvice (share/OG ruta iz §8.1).
  final String? focusSlug;

  const VotingScreen({super.key, this.focusSlug});

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {
  final VotingService _service = VotingService.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  Timer? _debounce;

  /// Jednokratni ekran „niz je pukao" (§8.2 stanje 5) — tap na CTA ga gasi.
  bool _brokenDismissed = false;

  bool _glasanjeUTijeku = false;
  bool _sheetOpened = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    AuthService.instance.addListener(_onServiceChanged);
    // Servis je singleton i pamti pretragu između ekrana, a kontroler se stvara
    // nanovo — bez sjemenovanja bi ljestvica ostala filtrirana prošlim upitom s
    // praznim poljem, dakle bez vidljivog razloga i bez načina da se filter
    // makne. Sjemenovanje ide PRIJE listenera da ne okine suvišan debounce.
    _searchCtrl.text = _service.query ?? '';
    _searchCtrl.addListener(_onSearchChanged);
    // Prvi ulazak: kolo + stanje + ljestvica. `ensureLoaded` dijeli Future s
    // ostalim pozivateljima (home chip, /account) pa se ne udvostručuje.
    _service.ensureLoaded().then((_) => _maybeOpenFocused());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _service.removeListener(_onServiceChanged);
    AuthService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Učitavanje
  // ---------------------------------------------------------------------------

  /// Svaki poziv ljestvice prvo osigura **kolo**.
  ///
  /// `loadLeaderboard` šalje `p_round_id: round?.id`; bez kola parametar ispada
  /// iz poziva (server tada uzme tekuće), a sa **starim** kolom bi vratio
  /// prošlu ljestvicu. Jedan `refresh` na prazno kolo to riješi prije nego se
  /// filter uopće pošalje.
  Future<void> _sOsvjezenimKolom(Future<void> Function() akcija) async {
    if (_service.round == null) {
      await _service.refresh(withLeaderboard: false);
    }
    await akcija();
  }

  Future<void> _promijeniSort(VoteSort sort) => _sOsvjezenimKolom(
        () => _service.loadLeaderboard(sort: sort, limit: _limit),
      );

  Future<void> _promijeniTag(String? tag) => _sOsvjezenimKolom(
        () => _service.loadLeaderboard(
          tag: tag,
          clearTag: tag == null,
          limit: _limit,
        ),
      );

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      final upit = _searchCtrl.text.trim();
      _sOsvjezenimKolom(
        () => _service.loadLeaderboard(
          query: upit,
          clearQuery: upit.isEmpty,
          limit: _limit,
        ),
      );
    });
  }

  /// Svih 181 kandidata stane u jedan poziv — stranicanje nije u ovom krugu, a
  /// bez njega deep-link `/glasanje/:slug` mora naći kandidata u prvoj stranici.
  static const int _limit = 250;

  /// Miče pretragu i filter po temi u **jednom** pozivu.
  ///
  /// `clear()` sinkrono okine listener i zakaže debounce, pa ga odmah gasimo —
  /// inače bi 320 ms kasnije stigao drugi (suvišan) dohvat s istim rezultatom.
  Future<void> _ocistiFiltere() async {
    _debounce?.cancel();
    _searchCtrl.clear();
    _debounce?.cancel();
    await _sOsvjezenimKolom(
      () => _service.loadLeaderboard(
        clearQuery: true,
        clearTag: true,
        limit: _limit,
      ),
    );
  }

  Future<void> _ponoviUcitavanje() async {
    // `ensureLoaded` se nakon neuspjeha NE ponavlja (Future je memoiziran), pa
    // gumb „Pokušaj ponovno" mora ići na `refresh`.
    await _service.refresh();
  }

  // ---------------------------------------------------------------------------
  // Glasanje
  // ---------------------------------------------------------------------------

  /// Ulazna točka s ekrana — **jedino** mjesto koje drži zastavicu «u tijeku».
  ///
  /// Guard stoji ovdje, a ne u [_izvrsiGlas], jer se tijelo zna pozvati
  /// rekurzivno (privola pa ponovni pokušaj): da je guard unutra, drugi bi
  /// prolaz odmah izletio i korisnik bi nakon prihvaćene privole ostao bez
  /// glasa, bez poruke i bez greške.
  Future<void> _glasaj(VoteCandidate kandidat, int smjer) async {
    if (_glasanjeUTijeku) return;
    setState(() => _glasanjeUTijeku = true);
    try {
      await _izvrsiGlas(kandidat, smjer);
    } finally {
      if (mounted) setState(() => _glasanjeUTijeku = false);
    }
  }

  Future<void> _izvrsiGlas(VoteCandidate kandidat, int smjer) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);

    // Privola iz §4.3 — jednokratno, prije prvog glasa. Modal je ovdje
    // dopušten jer ga je korisnik pozvao vlastitim tapom na 👍/👎.
    if ((_service.state?.needsConsent ?? false) && !await _prihvatiPrivolu()) {
      return;
    }

    try {
      final ishod = await _service.castVote(
        slug: kandidat.slug,
        direction: smjer,
      );
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      if (ishod.alreadyVotedToday) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.votingAlreadyVoted)),
        );
      } else {
        // Tri ishoda, ne dva: od 25.8.2026. `flags_burned > 0` može doći i uz
        // `streak_saved = false` (praznina veća od broja zastavica pojede sve,
        // a niz svejedno pukne — migracija 20260825122100). Bez zasebne poruke
        // zastavice bi nestale bez ijedne riječi.
        final String poruka;
        if (ishod.flagsBurned > 0) {
          poruka = ishod.streakSaved
              ? l.votingStreakSaved(ishod.flagsBurned)
              : l.votingStreakBrokeBurned(ishod.flagsBurned);
        } else {
          poruka = l.votingVoteRecorded;
        }
        messenger.showSnackBar(SnackBar(content: Text(poruka)));
      }
      // Tally se pomaknuo za sve — povuci svježu ljestvicu s istim filterima.
      await _service.loadLeaderboard(limit: _limit);
    } on VotingFailure catch (e) {
      if (!mounted) return;
      if (e.code == VotingErrorCode.termsNotAccepted) {
        // Server je vidio da privole nema (drugi uređaj) — ponudi je odmah, pa
        // ponovi glas. Rekurzija ide na tijelo bez guarda (vidi [_glasaj]).
        if (await _prihvatiPrivolu() && mounted) {
          await _izvrsiGlas(kandidat, smjer);
        }
        return;
      }
      messenger.hideCurrentSnackBar();
      // Poruka se razrješava u trenutku događaja → `appStrings` je ovdje
      // ispravan (CLAUDE.md: perzistentni tekst ide kroz context).
      messenger.showSnackBar(SnackBar(content: Text(_porukaGreske(e.code))));
    }
  }

  /// Pita za privolu i upiše je. `false` = korisnik je odustao ili je upis pao
  /// (poruka je već prikazana) — pozivatelj tada ne smije nastaviti s glasom.
  ///
  /// Jedna putanja za oba mjesta: klijentski predznak (`needsConsent`) i
  /// serverov `terms_not_accepted`. Upis je u `try` na obje strane — mrežna
  /// greška ovdje inače izleti kao neuhvaćena async iznimka.
  Future<bool> _prihvatiPrivolu() async {
    final messenger = ScaffoldMessenger.of(context);
    final pristanak = await _pitajZaPrivolu();
    if (!pristanak || !mounted) return false;
    try {
      await _service.acceptTerms();
      return true;
    } catch (e) {
      log('voting: acceptTerms failed: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(appStrings.votingErrorGeneric)),
      );
      return false;
    }
  }

  String _porukaGreske(VotingErrorCode code) => switch (code) {
        VotingErrorCode.notVerified => appStrings.votingErrorNotVerified,
        VotingErrorCode.candidateNotAvailable =>
          appStrings.votingErrorCandidateGone,
        VotingErrorCode.roundClosed => appStrings.votingErrorRoundClosed,
        _ => appStrings.votingErrorGeneric,
      };

  Future<bool> _pitajZaPrivolu() async {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rezultat = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.votingConsentTitle),
        content: Text(l.votingConsentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.croBlue,
              foregroundColor: Colors.white,
              side: AppTheme.brandRim(theme.brightness),
            ),
            child: Text(l.votingConsentAccept),
          ),
        ],
      ),
    );
    return rezultat ?? false;
  }

  Future<void> _potvrdiIdentitet() async {
    final messenger = ScaffoldMessenger.of(context);
    final rezultat = await AuthService.instance.signInWithCertilia(context);
    if (!mounted) return;
    if (rezultat.message != null && rezultat.message!.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(rezultat.message!)));
    }
    await _service.refresh();
  }

  // ---------------------------------------------------------------------------
  // Detalj kandidata
  // ---------------------------------------------------------------------------

  void _maybeOpenFocused() {
    if (_sheetOpened || widget.focusSlug == null || !mounted) return;
    final slug = widget.focusSlug!;
    final kandidat =
        _service.candidates.where((c) => c.slug == slug).firstOrNull;
    if (kandidat == null) return;
    _sheetOpened = true;
    _otvoriDetalj(kandidat);
  }

  void _otvoriDetalj(VoteCandidate kandidat) {
    // Browserov Back mijenja rutu ispod sheeta — vidi `closeOnRouteChange`.
    final navigator = Navigator.of(context);
    late final VoidCallback unsubscribe;
    unsubscribe = closeOnRouteChange(context, () {
      if (navigator.canPop()) navigator.pop();
    });
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _CandidateSheet(
        kandidat: kandidat,
        mode: _actionMode(),
        mojGlas: _mojGlasZa(kandidat.slug),
        round: _service.round,
        today: _service.today,
        onVote: _actionMode() == CandidateActionMode.vote
            ? (smjer) {
                Navigator.of(ctx).pop();
                _glasaj(kandidat, smjer);
              }
            : null,
      ),
    ).whenComplete(unsubscribe);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// Objasni zašto tap na 👍/👎 nije prošao. Snackbar je izravna potvrda
  /// korisnikove radnje, pa je dopušten (CLAUDE.md pravilo o nudge-evima).
  ///
  /// Bez ovoga tap na prigušeni gumb ne radi ništa vidljivo — jedini trag je
  /// rečenica u zaglavlju na vrhu ekrana, koju korisnik na dnu duge liste ne
  /// vidi (prijavljeno 25.8.2026.).
  void _objasniBlokadu(VoteCandidate kandidat) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(razlogBlokadeGlasa(
        // Jednokratni event-time resolve → `appStrings` je ovdje ispravan.
        l: appStrings,
        kandidat: kandidat,
        round: _service.round,
        today: _service.today,
      )),
    ));
  }

  CandidateActionMode _actionMode() {
    final state = _service.state;
    if (state == null || !state.verified) return CandidateActionMode.none;
    if (state.votedToday) return CandidateActionMode.spent;
    final round = _service.round;
    final today = _service.today;
    if (round != null && today != null && !round.acceptsVotesOn(today)) {
      return CandidateActionMode.spent;
    }
    return CandidateActionMode.vote;
  }

  int? _mojGlasZa(String slug) {
    final glas = _service.state?.todayVote;
    return glas != null && glas.slug == slug ? glas.direction : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final state = _service.state;
    final display = _service.displayFor();
    final stanje = resolveVotingHeaderState(
      state: state,
      display: display,
      brokenDismissed: _brokenDismissed,
    );
    final mode = _actionMode();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(l.votingScreenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l.commonBack,
          onPressed: () => backUp(context),
        ),
      ),
      body: Column(
        children: [
          buildVotingHeader(
            stanje: stanje,
            state: state,
            round: _service.round,
            today: _service.today,
            display: display,
            todayCandidateName: _imeDanasnjegKandidata(),
            onBrokenDismiss: () => setState(() => _brokenDismissed = true),
          ),
          _SearchField(controller: _searchCtrl),
          _SortChips(
            trenutni: _service.sort,
            onChanged: _promijeniSort,
          ),
          // Popis tagova drži servis — `ensureLoaded()` na drugom ulasku ne
          // notifira, pa bi popis izračunat u ovom `State`-u ostao prazan.
          if (_service.tags.isNotEmpty)
            _TagChips(
              tagovi: _service.tags,
              odabrani: _service.tag,
              onChanged: _promijeniTag,
            ),
          Expanded(child: _lista(mode)),
        ],
      ),
      // Trajna traka za neverificirane — jedina traka na ekranu, pa donji
      // SafeArea ide na nju (CLAUDE.md pravilo o slaganju donjih traka).
      bottomNavigationBar: (state?.verified ?? false)
          ? null
          : VotingVerifyBar(onVerify: _potvrdiIdentitet),
    );
  }

  String? _imeDanasnjegKandidata() {
    final slug = _service.state?.todayVote?.slug;
    if (slug == null) return null;
    return _service.candidates
        .where((c) => c.slug == slug)
        .map((c) => c.displayName)
        .firstOrNull;
  }

  Widget _lista(CandidateActionMode mode) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final kandidati = _service.candidates;

    if (kandidati.isEmpty && _service.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (kandidati.isEmpty) {
      final greska = _service.lastError != null;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                greska ? l.votingLoadFailed : l.votingEmpty,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (greska)
                FilledButton(
                  // `refresh`, ne `ensureLoaded` — memoizirani Future se nakon
                  // neuspjeha ne bi ponovio.
                  onPressed: _ponoviUcitavanje,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.croBlue,
                    foregroundColor: Colors.white,
                    side: AppTheme.brandRim(theme.brightness),
                  ),
                  child: Text(l.commonRetry),
                )
              else
                TextButton(
                  onPressed: _ocistiFiltere,
                  child: Text(l.votingEmptyClear),
                ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _ponoviUcitavanje,
      child: ListView.separated(
        // Padding je parametar liste, ne wrapper — sadržaj mora klizati do
        // fizičkog ruba ekrana (CLAUDE.md).
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        itemCount: kandidati.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        itemBuilder: (context, i) {
          final k = kandidati[i];
          return CandidateTile(
            candidate: k,
            mode: mode,
            mojGlas: _mojGlasZa(k.slug),
            onVote: _glasanjeUTijeku ? null : (smjer) => _glasaj(k, smjer),
            onBlocked: () => _objasniBlokadu(k),
            onOpen: () => _otvoriDetalj(k),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pretraga, sort chipovi, tag chipovi
// ---------------------------------------------------------------------------

class _SearchField extends StatelessWidget {
  final TextEditingController controller;

  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: l.votingSearchHint,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: l.commonClose,
                    onPressed: controller.clear,
                  ),
          ),
          isDense: true,
          filled: true,
          fillColor:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}

/// Ljestvica / Nasumično / Najmanje glasova — postoji zbog §3.1: uz 181
/// kandidata i jedan glas dnevno vrh se cementira, pa rep treba vlastiti ulaz.
class _SortChips extends StatelessWidget {
  final VoteSort trenutni;
  final ValueChanged<VoteSort> onChanged;

  const _SortChips({required this.trenutni, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        // Padding unutar scrollabla — chipovi moraju kliziti do ruba.
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final sort in VoteSort.values) ...[
            if (sort != VoteSort.values.first) const SizedBox(width: 8),
            _BrandChip(
              label: switch (sort) {
                VoteSort.leaderboard => l.votingSortLeaderboard,
                VoteSort.random => l.votingSortRandom,
                VoteSort.leastVotes => l.votingSortLeastVotes,
              },
              selected: sort == trenutni,
              onSelected: () => onChanged(sort),
            ),
          ],
        ],
      ),
    );
  }
}

class _TagChips extends StatelessWidget {
  final List<String> tagovi;
  final String? odabrani;
  final ValueChanged<String?> onChanged;

  const _TagChips({
    required this.tagovi,
    required this.odabrani,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _BrandChip(
            label: l.votingTagAll,
            selected: odabrani == null,
            onSelected: () => onChanged(null),
          ),
          for (final tag in tagovi) ...[
            const SizedBox(width: 8),
            _BrandChip(
              label: '#$tag',
              selected: tag == odabrani,
              onSelected: () => onChanged(tag == odabrani ? null : tag),
            ),
          ],
        ],
      ),
    );
  }
}

/// Brand-fill je navy (`AppTheme.croBlue`) + `brandRim()` — nikad `cs.primary`,
/// koji M3 u dark shemi izblijedi.
class _BrandChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _BrandChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: selected ? Colors.white : theme.colorScheme.onSurfaceVariant,
        ),
        selectedColor: AppTheme.croBlue,
        side: selected ? AppTheme.brandRim(theme.brightness) : BorderSide.none,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detalj kandidata (`/glasanje/:slug`)
// ---------------------------------------------------------------------------

class _CandidateSheet extends StatelessWidget {
  final VoteCandidate kandidat;
  final CandidateActionMode mode;
  final int? mojGlas;
  final ValueChanged<int>? onVote;

  /// Za objašnjenje zašto glasanje nije moguće — vidi [razlogBlokadeGlasa].
  final VoteRound? round;
  final DateTime? today;

  const _CandidateSheet({
    required this.kandidat,
    required this.mode,
    this.mojGlas,
    this.onVote,
    this.round,
    this.today,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          // Sekcije nose vlastiti h-padding; sheet padding bez horizontalne
          // komponente (isti obrazac kao founder_booking).
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    CandidateAvatar(candidate: kandidat, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            kandidat.displayName,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${kandidat.net > 0 ? '+' : ''}${kandidat.net} · '
                            '${l.votingVotesCount(kandidat.totalVotes)}',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (kandidat.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in kandidat.tags)
                        Chip(
                          label: Text('#$t'),
                          labelStyle: theme.textTheme.labelSmall,
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(color: cs.outlineVariant),
                        ),
                    ],
                  ),
                ),
              if (kandidat.voditelji.isNotEmpty)
                _redak(theme, l.votingHosts, kandidat.voditelji.join(', ')),
              if (kandidat.subscribers != null && kandidat.subscribers! > 0)
                _redak(
                  theme,
                  l.votingSubscribersLabel,
                  compactCount(kandidat.subscribers!, l),
                ),
              if (kandidat.episodesEstimate != null &&
                  kandidat.episodesEstimate! > 0)
                _redak(
                  theme,
                  l.votingEpisodesLabel,
                  '${kandidat.episodesEstimate}',
                ),
              if ((kandidat.notes ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    kandidat.notes!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    if (kandidat.youtubeUrl.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _otvoriYoutube(kandidat.youtubeUrl),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(l.commonOpenSource),
                      ),
                    const Spacer(),
                    if (mojGlas != null)
                      Text(
                        l.votingYourVoteToday,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.croBlue,
                        ),
                      )
                    else if (mode == CandidateActionMode.vote &&
                        kandidat.isVotable) ...[
                      IconButton(
                        onPressed: () => onVote?.call(kVoteDirectionUp),
                        icon: const Icon(Icons.thumb_up_outlined),
                        tooltip: l.votingVoteUp,
                        color: AppTheme.croBlue,
                      ),
                      IconButton(
                        onPressed: () => onVote?.call(kVoteDirectionDown),
                        icon: const Icon(Icons.thumb_down_outlined),
                        tooltip: l.votingVoteDown,
                        color: cs.onSurfaceVariant,
                      ),
                    ]
                    // Ne može glasati: prije je ovdje stajala praznina, pa je
                    // sheet izgledao kao da su gumbi jednostavno nestali.
                    else if (mode == CandidateActionMode.spent)
                      Flexible(
                        child: Text(
                          razlogBlokadeGlasa(
                            l: l,
                            kandidat: kandidat,
                            round: round,
                            today: today,
                          ),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _redak(ThemeData theme, String naziv, String vrijednost) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                naziv,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: Text(vrijednost, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      );

  Future<void> _otvoriYoutube(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      log('voting: launchUrl failed ($url): $e');
    }
  }
}

/// Zašto tap na 👍/👎 nije prošao — jedna rečenica, tri razloga.
///
/// Prima [l] umjesto da ga sam razrješava: snackbar na ekranu ga zove s
/// `appStrings` (jednokratni event-time resolve), a sheet s
/// `AppLocalizations.of(context)` jer se ondje renderira perzistentno
/// (CLAUDE.md pravilo o `appStrings`).
String razlogBlokadeGlasa({
  required AppLocalizations l,
  required VoteCandidate kandidat,
  required VoteRound? round,
  required DateTime? today,
}) {
  if (!kandidat.isVotable) return l.votingErrorCandidateGone;
  if (round != null && today != null && !round.acceptsVotesOn(today)) {
    return l.votingErrorRoundClosed;
  }
  return '${l.votingAlreadyVoted} ${l.votingComeBackTomorrow}';
}
