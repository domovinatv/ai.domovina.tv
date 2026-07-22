library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../onboarding/ui/auth_sheet.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/locale_service.dart';
import '../../../../widgets/account_chip.dart';
import '../../../../widgets/language_toggle_button.dart';
import '../../../../widgets/theme_toggle_button.dart';
import '../models/pinka_campaign.dart';
import '../models/pinka_public_contribution.dart';
import '../models/pinka_slot.dart';
import '../models/pinka_yield_position.dart';
import '../pinka_client.dart';
import '../pinka_config.dart';
import '../../../services/page_meta.dart';
import '../util/pinka_money.dart';
import '../util/pinka_onchain.dart';
import '../widgets/pinka_common.dart';
import '../widgets/pinka_contribute_panel.dart';
import '../widgets/pinka_grid_wall.dart';
import '../widgets/pinka_wall_list.dart';

/// Pun "Zid podrške" ekran — naslovnica, opis, stats, contribute panel
/// (SEPA + on-chain) i živi zid doprinosa. Subjekt-generičan: radi za kanal
/// (sad) i epizodu (vizija). Reimplementacija pinka.io `/c` stranice.
class PinkaCampaignScreen extends StatefulWidget {
  final String subjectType;
  final List<String> subjectRefs;

  /// Fallback naslov dok se kampanja ne učita (npr. ime kanala).
  final String? fallbackTitle;
  final PinkaClient client;
  final PinkaConfig config;

  PinkaCampaignScreen({
    super.key,
    required this.subjectType,
    required this.subjectRefs,
    this.fallbackTitle,
    PinkaClient? client,
    this.config = PinkaConfig.defaults,
  }) : client = client ?? PinkaClient.instance;

  /// Kanal: subject_ref = UC… id ILI domovina interni channel id (oba kandidata).
  PinkaCampaignScreen.channel({
    Key? key,
    required String channelId,
    String? youtubeChannelId,
    String? channelName,
    PinkaClient? client,
    PinkaConfig config = PinkaConfig.defaults,
  }) : this(
         key: key,
         subjectType: PinkaSubject.channel,
         subjectRefs: [channelId, ?youtubeChannelId],
         fallbackTitle: channelName,
         client: client,
         config: config,
       );

  /// Epizoda (vizija): subject_ref = YouTube video id.
  PinkaCampaignScreen.episode({
    Key? key,
    required String youtubeId,
    String? episodeTitle,
    PinkaClient? client,
    PinkaConfig config = PinkaConfig.defaults,
  }) : this(
         key: key,
         subjectType: PinkaSubject.episode,
         subjectRefs: [youtubeId],
         fallbackTitle: episodeTitle,
         client: client,
         config: config,
       );

  @override
  State<PinkaCampaignScreen> createState() => _PinkaCampaignScreenState();
}

class _PinkaCampaignScreenState extends State<PinkaCampaignScreen>
    with TickerProviderStateMixin {
  PinkaCampaign? _campaign;
  bool _loading = true;
  List<PinkaPublicContribution> _wall = const [];
  PinkaYieldPosition? _yield;
  int? _balanceCents;
  Set<String> _flashIds = {};
  final Set<String> _seen = {};
  bool _firstLoad = true;
  Timer? _timer;
  final ScrollController _wallScroll = ScrollController();
  final ScrollController _railScroll = ScrollController();

  /// Iznos odabran tapom na kvadratić zida (PinkaGridWall) + tick da se isti
  /// iznos smije primijeniti ponovno; ključ panela za scroll-to-panel.
  /// Koristi se SAMO u legacy modu (kampanja bez mape mjesta).
  int? _gridAmountCents;
  int _gridAmountTick = 0;
  final GlobalKey _panelKey = GlobalKey();

  /// Sidro zida za "let" nove donacije (cilj animacije); aktivni letovi da ih
  /// dispose ekrana može počistiti.
  final GlobalKey _wallKey = GlobalKey();
  final List<(AnimationController, OverlayEntry)> _flights = [];

  /// Mapa mjesta i zauzeta mjesta sa servera. `_slotMap == null` → legacy
  /// prikaz zida; grid mod se pali PODACIMA (seed mape), ne feature flagom.
  PinkaSlotMap? _slotMap;
  List<PinkaSlot>? _slots;

  /// Mjesto koje korisnik trenutno drži odabranim (`'60:60'`) + cijena i
  /// naziv zone za panel.
  String? _selectedSlotKey;
  int? _selectedSlotPriceCents;
  String? _selectedSlotLabel;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final f in List.of(_flights)) {
      _cleanupFlight(f);
    }
    _wallScroll.dispose();
    _railScroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final c = await widget.client.campaignForSubject(
      subjectType: widget.subjectType,
      subjectRefs: widget.subjectRefs,
    );
    if (!mounted) return;
    if (c == null) {
      setState(() {
        _campaign = null;
        _loading = false;
      });
      return;
    }
    final list = await widget.client.wall(c.id);
    final yield_ = await widget.client.yieldPosition(c.id);
    // Mapa se dohvaća jednom (mijenja se samo seedom/brisanjem na backendu);
    // mjesta na svakom osvježavanju jer je to živo stanje zida.
    final map = _slotMap ?? await widget.client.slotMap(c.id);
    final slots = map == null ? null : await widget.client.slots(c.id);
    // Live on-chain EURe saldo Safe-a (uz kumulativni "prikupljeno") — čita se
    // direktno s javnog Gnosis RPC-a, null na grešku → red se ne prikaže.
    final balance = c.supportsOnchain
        ? await fetchEureBalanceCents(
            rpcUrl: widget.config.gnosisRpcUrl,
            eureAddress: widget.config.eureAddress,
            address: c.destinationAddress!,
          )
        : null;
    if (!mounted) return;
    // Runtime <title>/og meta za živu sesiju (crawleri idu kroz _worker.js
    // koji isti naslov gradi edge-side iz kampanje).
    setPageMeta(title: '${c.title} – DOMOVINA.ai', description: c.description);
    setState(() {
      _campaign = c;
      _loading = false;
      _wall = list;
      _yield = yield_;
      _balanceCents = balance ?? _balanceCents;
      _slotMap = map;
      _slots = slots;
    });
    if (_firstLoad) {
      _seen.addAll(list.map((e) => e.id));
      _firstLoad = false;
      return;
    }
    final fresh = list
        .where((e) => !_seen.contains(e.id))
        .map((e) => e.id)
        .toSet();
    if (fresh.isNotEmpty) {
      _seen.addAll(fresh);
      setState(() => _flashIds = fresh);
      Future.delayed(const Duration(milliseconds: 2400), () {
        if (mounted) setState(() => _flashIds = {});
      });
    }
  }

  /// Kanonski javni link na ovaj zid — kanal: `/c/<slug>/support` (interni id
  /// s podvlakama → slug s crticama), epizoda: `/v/<ytId>/support`.
  String get _shareUrl {
    final ref = widget.subjectRefs.first;
    // Share link prati aktivni UI jezik: HR dijeli /doniraj, EN /support
    // (obje rute vode na isti ekran — vidi app_router.dart).
    final action = LocaleController.instance.isEnglish ? 'support' : 'doniraj';
    final path = widget.subjectType == PinkaSubject.channel
        ? '/c/${ref.replaceAll('_', '-')}/$action'
        : '/v/$ref/$action';
    return '${widget.config.shareBaseUrl}$path';
  }

  /// Tap na slobodan kvadratić zida (LEGACY mod): postavi iznos u panel za
  /// uplatu, dovuci panel u vidno polje i potvrdi snackbarom.
  void _onGridZoneTap(int amountCents, String zoneName) {
    setState(() {
      _gridAmountCents = amountCents;
      _gridAmountTick++;
    });
    _revealPanel();
    _toast(appStrings.pinkaGridAmountSet(zoneName, fmtEur(amountCents)));
  }

  /// Tap na slobodno mjesto (SERVER mod): odabir se pamti i prosljeđuje
  /// panelu, koji zaključava iznos na cijenu mjesta. Rezervacija nastaje tek
  /// pri kreiranju doprinosa — dotad je ovo samo namjera.
  void _onSlotTap(String slotKey, int priceCents, String zoneName) {
    final coords = slotKey.replaceAll(':', ' · ');
    setState(() {
      _selectedSlotKey = slotKey;
      _selectedSlotPriceCents = priceCents;
      _selectedSlotLabel = '$zoneName · $coords';
    });
    _revealPanel();
    _toast(appStrings.pinkaGridAmountSet(zoneName, fmtEur(priceCents)));
  }

  void _clearSlot() {
    setState(() {
      _selectedSlotKey = null;
      _selectedSlotPriceCents = null;
      _selectedSlotLabel = null;
    });
  }

  /// Mjesto je preoteto dok je korisnik birao — očisti odabir i odmah povuci
  /// svježu mapu da preoteta ćelija pocrveni.
  void _onSlotConflict(String? slotKey) {
    _clearSlot();
    _refresh();
  }

  void _revealPanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _panelKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.05,
      );
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// "Poleti" mini karticu doprinosa iz panela (gdje je donator upravo gledao
  /// progress 5/5) prema vrhu zida — vizualni dolazak donacije u listu.
  void _flyDonationToWall(int amountCents, String? displayName) {
    final panelBox = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (panelBox == null || !panelBox.attached || overlayState == null) return;
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final screen = overlayBox.size;

    // Start: sredina panela, gdje je stajao stepper/potvrda.
    final start =
        panelBox.localToGlobal(panelBox.size.center(Offset.zero)) -
        const Offset(80, 20);

    // Cilj: vrh zida — najnoviji unos ide na početak liste. Kad je zid izvan
    // ekrana (mobile, daleko ispod), klampanje drži cilj na rubu viewporta pa
    // se i dalje vidi smjer leta.
    final wallBox = _wallKey.currentContext?.findRenderObject() as RenderBox?;
    var end = (wallBox != null && wallBox.attached)
        ? wallBox.localToGlobal(const Offset(12, 12))
        : Offset(24, screen.height - 96);
    end = Offset(
      end.dx.clamp(12.0, math.max(12.0, screen.width - 220.0)),
      end.dy.clamp(12.0, math.max(12.0, screen.height - 72.0)),
    );

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    final curve = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );
    // Kvadratni bézier s kontrolnom točkom iznad spojnice — blagi luk.
    final control = Offset(
      (start.dx + end.dx) / 2,
      math.min(start.dy, end.dy) - 100,
    );

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: curve,
        builder: (context, _) {
          final t = curve.value;
          final u = 1 - t;
          final pos = start * (u * u) + control * (2 * u * t) + end * (t * t);
          // Zadnjih 15% puta kartica se "stopi" u zid (fade + blagi shrink).
          final fade = t < 0.85 ? 1.0 : (1 - t) / 0.15;
          return Positioned(
            left: pos.dx,
            top: pos.dy,
            child: IgnorePointer(
              child: Opacity(
                opacity: fade.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 1 - 0.2 * t,
                  alignment: Alignment.topLeft,
                  child: _FlyingDonationChip(
                    amountCents: amountCents,
                    displayName: displayName,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    final flight = (controller, entry);
    _flights.add(flight);
    overlayState.insert(entry);
    controller.forward().whenCompleteOrCancel(() => _cleanupFlight(flight));
  }

  /// Skini overlay i oslobodi controller — idempotentno (let završi sam ILI
  /// ga počisti dispose ekrana, što god dođe prvo).
  void _cleanupFlight((AnimationController, OverlayEntry) flight) {
    if (!_flights.remove(flight)) return;
    final (controller, entry) = flight;
    controller.stop();
    if (entry.mounted) entry.remove();
    controller.dispose();
  }

  void _copyShareLink() {
    Clipboard.setData(ClipboardData(text: _shareUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(appStrings.commonLinkCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        // Naslov kampanje živi u tijelu ekrana — AppBar je generički da se
        // "Podrži …" ne pojavljuje duplo.
        title: Text(l.pinkaWallTitle),
        // Iste akcije kao home app bar (jezik/tema/profil) + share kampanje —
        // korisnik se s doniraj ekrana prijavljuje i mijenja temu bez odlaska
        // na home. AccountChip pokazuje "Prijava" (gost) ili avatar menu.
        actions: [
          const LanguageToggleButton(),
          const SizedBox(width: 4),
          const ThemeToggleButton(),
          if (_campaign != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: l.commonCopyLink,
              onPressed: _copyShareLink,
            ),
          ],
          const SizedBox(width: 4),
          const AccountChip(),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _campaign == null
          ? _empty(theme)
          : _content(theme, _campaign!),
    );
  }

  Widget _empty(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          l.pinkaNoCampaign,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _content(ThemeData theme, PinkaCampaign c) {
    final l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final stats = _statsCard(theme, c);
        final panel = PinkaContributePanel(
          key: _panelKey,
          campaign: c,
          client: widget.client,
          config: widget.config,
          // Uplata je sjela → mjesto je prešlo u `sold`; odmah povuci svježu
          // mapu da se ime pojavi na kvadratiću, očisti odabir i animiraj
          // "dolazak" doprinosa na zid.
          onPaid: (amountCents, displayName) {
            _clearSlot();
            _refresh();
            _flyDonationToWall(amountCents, displayName);
          },
          signedInName: () => AuthService.instance.isSignedIn
              ? AuthService.instance.currentUser?.displayName
              : null,
          onSignInRequested: (ctx) => showAuthSheet(ctx),
          presetAmountCents: _gridAmountCents,
          presetAmountTick: _gridAmountTick,
          selectedSlotKey: _selectedSlotKey,
          selectedSlotPriceCents: _selectedSlotPriceCents,
          selectedSlotLabel: _selectedSlotLabel,
          onClearSlot: _clearSlot,
          onSlotConflict: _onSlotConflict,
        );
        // Semantics identifieri (pinka-*) izlaze kao flt-semantics-identifier
        // atribut u a11y DOM-u → stabilna hvatišta za Playwright/Cypress i
        // screen readere. Bez aktivnog semantics stabla nemaju runtime trošak.
        final grid = Semantics(
          identifier: 'pinka-grid-wall',
          container: true,
          child: PinkaGridWall(
            contributions: _wall,
            map: _slotMap,
            slots: _slots,
            selectedSlotKey: _selectedSlotKey,
            onSlotTap: _onSlotTap,
            onZoneTap: _onGridZoneTap,
          ),
        );
        final verify = c.supportsOnchain ? _verifyCard(theme, c) : null;
        final main = _mainColumn(theme, c);

        if (!wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                stats,
                // Zid kvadratića prije panela — posjetitelj prvo vidi ŠTO
                // kupuje, pa tek onda gumb za uplatu.
                const SizedBox(height: 12),
                grid,
                const SizedBox(height: 12),
                panel,
                if (verify != null) ...[const SizedBox(height: 12), verify],
                const SizedBox(height: 24),
                main,
              ],
            ),
          );
        }

        // Desktop: sve stane u viewport — stranica NE scrolla. Tri stupca:
        // zid (primarni, lijevo; scroll interno do samog donjeg ruba ekrana),
        // sredina = naslov/opis kampanje + on-chain verifikacija, desno rail
        // (stats + uplata; scrolla samo ako mu ponestane visine).
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.pinkaWallTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: KeyedSubtree(
                        key: _wallKey,
                        child: _wall.isEmpty
                            ? Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  l.pinkaWallEmpty,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : Scrollbar(
                                controller: _wallScroll,
                                child: SingleChildScrollView(
                                  controller: _wallScroll,
                                  // Margine žive UNUTAR scroll sadržaja — viewport
                                  // ide do ruba ekrana pa se kartice ne "režu" na
                                  // vanjskom marginu pri scrollu.
                                  padding: const EdgeInsets.only(
                                    right: 16,
                                    bottom: 24,
                                  ),
                                  child: PinkaWallList(
                                    contributions: _wall,
                                    flashIds: _flashIds,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            SizedBox(
              width: 340,
              // Vertikalne margine su content padding UNUTAR scrolla (kao kod
              // zida lijevo) — viewport ide do ruba pa se sadržaj ne "reže".
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    grid,
                    const SizedBox(height: 16),
                    _wideHeader(theme, c),
                    const SizedBox(height: 16),
                    stats,
                    if (verify != null) ...[const SizedBox(height: 12), verify],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            SizedBox(
              width: 360,
              child: SingleChildScrollView(
                controller: _railScroll,
                padding: const EdgeInsets.fromLTRB(0, 16, 24, 20),
                child: panel,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Kompaktni header za desktop: mala cover sličica uz naslov, opis
  /// ograničen na 3 retka — da zid i uplata ostanu u viewportu bez scrolla.
  Widget _wideHeader(ThemeData theme, PinkaCampaign c) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (c.description != null && c.description!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            c.description!,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ],
    );
    if (c.coverImageUrl == null) return text;
    // Srednji stupac je uzak (340) — cover ide iznad teksta, punom širinom.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              c.coverImageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        text,
      ],
    );
  }

  Widget _mainColumn(ThemeData theme, PinkaCampaign c) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.coverImageUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                c.coverImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          c.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (c.description != null && c.description!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            c.description!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          l.pinkaWallTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (_wall.isEmpty)
          Text(
            l.pinkaWallEmpty,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          KeyedSubtree(
            key: _wallKey,
            child: PinkaWallList(contributions: _wall, flashIds: _flashIds),
          ),
      ],
    );
  }

  Widget _statsCard(ThemeData theme, PinkaCampaign c) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${fmtEur(c.totalRaisedCents)} €',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (c.hasGoal) ...[
            const SizedBox(height: 4),
            Text(
              l.pinkaOfGoal(fmtEur(c.goalCents!)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: c.progress,
                minHeight: 9,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: theme.colorScheme.tertiary,
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              l.pinkaRaisedLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '${l.pinkaSupportersCount(c.contributorCount)}'
            ' · ${l.pinkaPaymentsCount(c.contributionCount)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verifyCard(ThemeData theme, PinkaCampaign c) {
    final l = AppLocalizations.of(context);
    final dest = c.destinationAddress!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.pinkaVerifyOnchainTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_balanceCents != null) ...[
            const SizedBox(height: 6),
            Text(
              l.pinkaOnchainBalance(fmtEur(_balanceCents!)),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.tertiary,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            l.pinkaVerifyOnchainBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              alignment: Alignment.centerLeft,
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(l.pinkaEureBalanceOnGnosisscan),
            onPressed: () => pinkaLaunch(widget.config.tokenBalanceUrl(dest)),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              alignment: Alignment.centerLeft,
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(l.pinkaInflowHistory),
            onPressed: () => pinkaLaunch(widget.config.tokenTxnsUrl(dest)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                // Cijela adresa u jednom retku bez lomljenja/elipse — skalira
                // se prema širini kartice.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    dest,
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 16),
                tooltip: l.pinkaCopySafeAddress,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: dest));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(appStrings.pinkaSafeAddressCopied),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          if (_yield != null && _yield!.isDeployed) _aaveSection(theme, dest),
        ],
      ),
    );
  }

  /// Kad su sredstva parkirana na Aaveu, EURe saldo na Safeu je nizak (drže se
  /// kao aGnoEURe) — pokaži poziciju da donori vide da novac "radi", ne da je nestao.
  Widget _aaveSection(ThemeData theme, String dest) {
    final l = AppLocalizations.of(context);
    final y = _yield!;
    final inAave = y.lastBalanceCents > 0
        ? y.lastBalanceCents
        : y.principalCents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Divider(color: theme.colorScheme.outlineVariant, height: 1),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.savings_outlined,
              size: 16,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l.pinkaFundsWorkingAave,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${l.pinkaInAaveLabel(fmtEur(inAave))}'
          '${y.accruedYieldCents > 0 ? ' · ${l.pinkaAaveYieldLabel(fmtEur(y.accruedYieldCents))}' : ''}. '
          '${l.pinkaAaveExplainer}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (y.atokenAddress != null)
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              alignment: Alignment.centerLeft,
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(l.pinkaAgnoEureBalanceOnGnosisscan),
            onPressed: () => pinkaLaunch(
              widget.config.tokenForAddressUrl(y.atokenAddress!, dest),
            ),
          ),
      ],
    );
  }
}

/// Mini kartica doprinosa koja "leti" iz panela na zid — ista vizualna
/// obitelj kao unos u [PinkaWallList], samo kompaktna (ime + iznos).
class _FlyingDonationChip extends StatelessWidget {
  final int amountCents;
  final String? displayName;

  const _FlyingDonationChip({
    required this.amountCents,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.tertiary.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite, size: 16, color: cs.tertiary),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                displayName ?? l.pinkaAnonymous,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onTertiaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${fmtEur(amountCents)} €',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.tertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
