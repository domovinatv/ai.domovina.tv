library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../services/locale_service.dart';
import '../models/pinka_campaign.dart';
import '../models/pinka_contribution_intent.dart';
import '../models/pinka_slot.dart';
import '../pinka_client.dart';
import '../pinka_config.dart';
import '../util/pinka_intent_status.dart';
import '../util/pinka_money.dart';
import '../wallet/pinka_wallet.dart';
import 'pinka_common.dart';

/// "Podrži" panel — SEPA (EPC QR) + on-chain (EURe na Gnosisu preko MPT
/// protokola) doprinos. Samostalan: prima kampanju, javlja [onPaid] kad uplata
/// sjedne (host osvježi zid). Reimplementacija pinka.io `ContributePanel`.
class PinkaContributePanel extends StatefulWidget {
  final PinkaCampaign campaign;
  final PinkaClient client;
  final PinkaConfig config;

  /// Poziva se kad uplata sjedne — s iznosom i javnim imenom donatora
  /// (null = anonimno), da host može animirati "dolazak" doprinosa na zid.
  final void Function(int amountCents, String? displayName)? onPaid;

  /// Host hook: display-name prijavljenog korisnika ili `null` (gost/anon).
  /// Kad je ne-null, ime donatora se predispuni; kad je null, uz polje se
  /// nudi "Prijavi se" gumb (vidi [onSignInRequested]).
  final String? Function()? signedInName;

  /// Host hook: otvori auth flow aplikacije (auth sheet). Nakon što se
  /// vrati, panel ponovno pročita [signedInName] i predispuni ime.
  final Future<void> Function(BuildContext context)? onSignInRequested;

  /// Iznos preselektiran izvana (tap na kvadratić zida — PinkaGridWall).
  /// Primjenjuje se kad [presetAmountTick] poraste, pa isti iznos smije
  /// biti postavljen više puta zaredom (npr. korisnik ručno promijeni
  /// iznos pa ponovno tapne istu zonu).
  final int? presetAmountCents;
  final int presetAmountTick;

  /// Mjesto odabrano na zidu (`'60:60'`) — kad je postavljeno, iznos je
  /// ZAKLJUČAN na [selectedSlotPriceCents] (nadoplata gore je OK, ispod nije:
  /// server odbija s `amount_below_slot_price`).
  final String? selectedSlotKey;
  final int? selectedSlotPriceCents;

  /// Ljudski čitljiv opis odabranog mjesta ("Zlatni krug · 60 · 60").
  final String? selectedSlotLabel;

  /// Korisnik odustaje od mjesta i vraća se na obične iznose.
  final VoidCallback? onClearSlot;

  /// Mjesto je preoteto dok je korisnik birao — host osvježi mapu i očisti
  /// odabir. Prima ključ mjesta koje je palo (može biti `null`).
  final void Function(String? slotKey)? onSlotConflict;

  const PinkaContributePanel({
    super.key,
    required this.campaign,
    required this.client,
    required this.config,
    this.onPaid,
    this.signedInName,
    this.onSignInRequested,
    this.presetAmountCents,
    this.presetAmountTick = 0,
    this.selectedSlotKey,
    this.selectedSlotPriceCents,
    this.selectedSlotLabel,
    this.onClearSlot,
    this.onSlotConflict,
  });

  @override
  State<PinkaContributePanel> createState() => _PinkaContributePanelState();
}

enum _Mode { sepa, onchain }

enum _Phase { idle, creating, awaiting, paid }

enum _WalletPhase { idle, connecting, sending, confirming }

class _PinkaContributePanelState extends State<PinkaContributePanel> {
  static const _presetsCents = [100, 200, 500, 1000, 2000];
  static const _nameMax = 60;
  static const _msgMax = 280;
  static const _linkMax = 200;

  _Mode _mode = _Mode.sepa;
  _Phase _phase = _Phase.idle;
  _WalletPhase _walletPhase = _WalletPhase.idle;

  int _amountCents = 500;
  final _customCtrl = TextEditingController();
  final _customFocus = FocusNode();
  final _nameCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  bool _anonymous = false;

  String? _error;
  String? _walletNote;
  PinkaContributionIntent? _intent;

  /// Živi rail progress SEPA intenta (stepper "Korak M/N" ispod QR-a).
  PinkaIntentStatus? _intentStatus;
  Timer? _statusTimer;

  /// Do kada je mjesto rezervirano (hold) — odbrojava se ispod QR-a.
  DateTime? _holdExpiresAt;
  Timer? _holdTimer;

  PinkaCampaign get _c => widget.campaign;

  bool get _hasSlot => widget.selectedSlotKey != null;

  /// Ime kako će pisati na zidu — null za anonimne/prazno polje.
  String? get _publicDisplayName {
    if (_anonymous) return null;
    final n = _nameCtrl.text.trim();
    return n.isEmpty ? null : n;
  }

  /// Poveznica kako ide backendu — null za anonimne, prazno ili nevaljano
  /// polje. Ista normalizacija koju vidi i živi pregled.
  String? get _publicLinkUrl =>
      _anonymous ? null : _normalizeLink(_linkCtrl.text);

  /// Poruka koja ide backendu. **Privremeni most**: `pinka-webhook` vadi OG
  /// preview isključivo iz `message` (`link_url` još nije izvor istine — task
  /// B), pa poveznicu dopisujemo na kraj poruke. Bez toga bi novo polje bilo
  /// regresija: danas ljudi zalijepe URL u poruku i dobiju preview. Kad
  /// webhook počne čitati `link_url`, ovaj append se briše.
  String? get _messageWithLink {
    if (_anonymous) return null;
    final msg = _msgCtrl.text.trim();
    final link = _publicLinkUrl;
    final fallback = msg.isEmpty ? null : msg;
    if (link == null) return fallback;
    final typed = _linkCtrl.text.trim();
    if (msg.contains(link) || msg.contains(typed)) return msg;
    final joined = msg.isEmpty ? link : '$msg $link';
    // Ako ne stane u polje poruke, poveznica ide SAMO kao `link_url`.
    return joined.length <= _msgMax ? joined : fallback;
  }

  /// Upisano, ali ne parsira kao `https://…` → blokira slanje.
  bool get _linkIsInvalid =>
      _linkCtrl.text.trim().isNotEmpty && _normalizeLink(_linkCtrl.text) == null;

  /// Donja granica iznosa: minimum kampanje, a uz odabrano mjesto i njegova
  /// cijena (server odbija manjak s `amount_below_slot_price`).
  int get _minCents =>
      math.max(_c.minContributionCents, widget.selectedSlotPriceCents ?? 0);

  @override
  void initState() {
    super.initState();
    if (_c.minContributionCents > _amountCents) {
      _amountCents = _c.minContributionCents;
    }
    _customFocus.addListener(_onCustomFocus);
    _prefillFromAuth();
    if (widget.selectedSlotPriceCents != null) {
      _applyPresetAmount(widget.selectedSlotPriceCents!);
    } else if (widget.presetAmountCents != null) {
      _applyPresetAmount(widget.presetAmountCents!);
    }
  }

  @override
  void didUpdateWidget(covariant PinkaContributePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Novo mjesto → iznos se zaključava na njegovu cijenu.
    if (widget.selectedSlotKey != oldWidget.selectedSlotKey &&
        widget.selectedSlotPriceCents != null) {
      setState(() => _applyPresetAmount(widget.selectedSlotPriceCents!));
    } else if (widget.presetAmountTick != oldWidget.presetAmountTick &&
        widget.presetAmountCents != null) {
      setState(() => _applyPresetAmount(widget.presetAmountCents!));
    }
  }

  /// Iznosi preset čipova biraju čip (custom polje se čisti); ostali iznosi
  /// (npr. skuplje zone zida) upišu se u "Ostalo" da UI odražava odabir.
  void _applyPresetAmount(int cents) {
    _amountCents = cents;
    // Uz odabrano mjesto nema čipova, pa polje MORA pokazati iznos — inače bi
    // ostalo prazno kad se cijena zone poklopi s presetom.
    if (_hasSlot) {
      _customCtrl.text = fmtEur(cents);
    } else if (_presetsCents.contains(cents)) {
      _customCtrl.clear();
    } else {
      _customCtrl.text = fmtEur(cents);
    }
  }

  /// Predispuni ime donatora iz prijavljenog identiteta — samo dok je polje
  /// prazno (donator uvijek smije obrisati/promijeniti što piše na zidu).
  void _prefillFromAuth() {
    final name = widget.signedInName?.call();
    if (name != null && name.isNotEmpty && _nameCtrl.text.isEmpty) {
      _nameCtrl.text = name;
    }
  }

  Future<void> _signIn() async {
    final open = widget.onSignInRequested;
    if (open == null) return;
    await open(context);
    if (!mounted) return;
    setState(_prefillFromAuth); // i sakrij "Prijavi se" ako je prijava uspjela
  }

  /// Fokus na prazno "Ostalo" polje predispuni predloženim iznosom (19,91),
  /// selektiranim u cijelosti da ga tipkanje odmah zamijeni.
  void _onCustomFocus() {
    if (!_customFocus.hasFocus || _customCtrl.text.isNotEmpty) return;
    final suggested = appStrings.pinkaCustomAmountPlaceholder;
    _customCtrl.value = TextEditingValue(
      text: suggested,
      selection: TextSelection(baseOffset: 0, extentOffset: suggested.length),
    );
    _setAmountFromCustom(suggested);
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _holdTimer?.cancel();
    _customFocus.dispose();
    _customCtrl.dispose();
    _nameCtrl.dispose();
    _linkCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  void _setAmountFromCustom(String raw) {
    final c = parseEurToCents(raw);
    if (c != null) setState(() => _amountCents = c);
  }

  /// Iznos ispod donje granice → poruka koja kaže ZAŠTO (cijena mjesta vs.
  /// minimum kampanje). Vraća `true` kad je iznos u redu.
  bool _validateAmount({required bool onchain}) {
    if (_amountCents >= _minCents) return true;
    final msg = _hasSlot
        ? appStrings.pinkaSlotBelowPrice(fmtEur(_minCents))
        : appStrings.pinkaMinAmount(fmtEur(_minCents));
    setState(() {
      if (onchain) {
        _walletNote = msg;
      } else {
        _error = msg;
      }
    });
    return false;
  }

  /// Nevaljana poveznica ne smije doći do backenda (worker ima `safeUrl`, ali
  /// donator zaslužuje reći ODMAH, prije QR-a). Vraća `true` kad je u redu.
  bool _validateLink({required bool onchain}) {
    if (!_linkIsInvalid) return true;
    final msg = appStrings.pinkaLinkInvalid;
    setState(() {
      if (onchain) {
        _walletNote = msg;
      } else {
        _error = msg;
      }
    });
    return false;
  }

  /// Kreira pending doprinos (+ rezervira mjesto ako je odabrano). Vraća
  /// `null` kad je mjesto preoteto — panel je tada već prikazao poruku i
  /// javio hostu da osvježi mapu.
  Future<PinkaContributionIntent?> _createContribution() async {
    try {
      return await widget.client.contribute(
        campaignId: _c.id,
        amountCents: _amountCents,
        displayName: _anonymous ? null : _nameCtrl.text,
        message: _messageWithLink,
        linkUrl: _publicLinkUrl,
        anonymous: _anonymous,
        slotKeys: widget.selectedSlotKey == null
            ? null
            : [widget.selectedSlotKey!],
      );
    } on PinkaSlotTaken catch (e) {
      if (!mounted) return null;
      setState(() {
        _phase = _Phase.idle;
        _walletPhase = _WalletPhase.idle;
        _error = appStrings.pinkaSlotTakenError;
        _walletNote = appStrings.pinkaSlotTakenError;
      });
      widget.onSlotConflict?.call(e.slotKey ?? widget.selectedSlotKey);
      return null;
    }
  }

  // ── SEPA ───────────────────────────────────────────────────────────────
  Future<void> _submitSepa() async {
    if (!_validateAmount(onchain: false)) return;
    if (!_validateLink(onchain: false)) return;
    setState(() {
      _phase = _Phase.creating;
      _error = null;
    });
    try {
      final intent = await _createContribution();
      if (intent == null || !mounted) return;
      setState(() {
        _intent = intent;
        _phase = _Phase.awaiting;
      });
      _startStatusPolling(intent);
      _startHoldCountdown(intent.holdExpiresAt);
      final paid = await widget.client.waitForPaid(intent.contributionId);
      if (!mounted) return;
      _statusTimer?.cancel();
      _holdTimer?.cancel();
      if (paid) {
        setState(() => _phase = _Phase.paid);
        widget.onPaid?.call(_amountCents, _publicDisplayName);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = appStrings.pinkaPaymentCreateFailed;
      });
    }
  }

  /// Odbrojavanje holda ispod QR-a — donator vidi koliko mu vremena mjesto
  /// stoji rezervirano. Istek NIJE gubitak novca: kasna uplata se i dalje
  /// kreditira, a mjesto se vraća ili premješta u istu/skuplju zonu.
  void _startHoldCountdown(DateTime? expiresAt) {
    _holdTimer?.cancel();
    if (expiresAt == null) return;
    setState(() => _holdExpiresAt = expiresAt);
    _holdTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {}); // samo osvježi prikaz preostalog vremena
    });
  }

  /// Polla rail status endpoint (`/api/intents/<sid>`) svake 3 s dok QR čeka
  /// uplatu — puni stepper "Korak M/N". Ukras uz `waitForPaid` (RPC ostaje
  /// izvor istine za "plaćeno"); na grešku fetch vrati null i UI zadrži
  /// zadnje poznato stanje / generički spinner.
  void _startStatusPolling(PinkaContributionIntent intent) {
    final url = intent.statusUrl ??
        (intent.sid.isNotEmpty
            ? '${widget.config.intentStatusBase}${intent.sid}'
            : null);
    if (url == null) return;
    _statusTimer?.cancel();
    Future<void> tick() async {
      final s = await fetchIntentStatus(url);
      if (!mounted || _phase != _Phase.awaiting) return;
      if (s != null) setState(() => _intentStatus = s);
    }

    tick();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) => tick());
  }

  // ── On-chain (in-app DOMOVINA wallet) ────────────────────────────────────
  Future<void> _payFromWallet() async {
    final dest = _c.destinationAddress;
    if (dest == null) return;
    if (!_validateAmount(onchain: true)) return;
    // Uz odabrano mjesto i on-chain putanja inserta doprinos (s porukom i
    // poveznicom), pa validacija vrijedi i ovdje.
    if (_hasSlot && !_validateLink(onchain: true)) return;
    setState(() {
      _walletNote = null;
      _walletPhase = _WalletPhase.connecting;
    });
    try {
      // Uz odabrano mjesto uplata mora kreditirati KONKRETAN pending doprinos
      // (onaj koji drži hold). Bez toga backend inserta novi doprinos, hold
      // istekne i korisnik plati bez kvadratića.
      String? contributionId;
      if (_hasSlot) {
        final intent = await _createContribution();
        if (intent == null || !mounted) return;
        contributionId = intent.contributionId;
        setState(() => _holdExpiresAt = intent.holdExpiresAt);
      }
      // Osiguraj povezani novčanik. Prvi put (bez keša) ovo radi full-page
      // handoff na wallet.domovina.ai i ne vrati se — korisnik se vrati i
      // ponovno tapne "Plati" (tada je identitet keširan pa je instant).
      await pinkaWalletConnect(sdkUrl: widget.config.walletSdkUrl);
      if (!mounted) return;
      setState(() => _walletPhase = _WalletPhase.sending);
      final txHash = await pinkaWalletSend(
        to: dest,
        amount: (_amountCents / 100).toStringAsFixed(2),
        sdkUrl: widget.config.walletSdkUrl,
      );
      if (!mounted) return;
      setState(() => _walletPhase = _WalletPhase.confirming);
      // Poll verifier dok tx ne mine + kreditira (~Gnosis 5s blokovi).
      for (var i = 0; i < 20; i++) {
        final r = await widget.client.confirmOnchain(
          campaignId: _c.id,
          txHash: txHash,
          contributionId: contributionId,
        );
        if (r.reverted) throw StateError('reverted');
        if (r.isCredited) {
          if (!mounted) return;
          setState(() => _phase = _Phase.paid);
          widget.onPaid?.call(_amountCents, _publicDisplayName);
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      if (!mounted) return;
      setState(() {
        _walletPhase = _WalletPhase.idle;
        _walletNote = appStrings.pinkaPaymentSentPending;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _walletPhase = _WalletPhase.idle;
        _walletNote = appStrings.pinkaWalletSendFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: switch (_phase) {
        _Phase.awaiting => _buildSepaQr(theme),
        _Phase.paid => _buildPaid(theme),
        _ => _buildForm(theme),
      },
    );
  }

  Widget _buildForm(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final creating = _phase == _Phase.creating;
    final onchain = _mode == _Mode.onchain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.volunteer_activism,
                color: theme.colorScheme.tertiary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l.pinkaSupport,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        if (_c.supportsOnchain) ...[
          const SizedBox(height: 12),
          _modeToggle(theme),
        ],
        const SizedBox(height: 6),
        Text(
          onchain ? l.pinkaOnchainBlurb : l.pinkaSepaBlurb,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _amountPicker(theme),
        if (!onchain) ...[
          const SizedBox(height: 12),
          _identityFields(theme),
          const SizedBox(height: 14),
          _previewSection(theme),
        ],
        if (_error != null && !onchain) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 12),
        if (onchain) _onchainSection(theme) else _sepaButton(theme, creating),
      ],
    );
  }

  Widget _modeToggle(ThemeData theme) {
    return SegmentedButton<_Mode>(
      segments: const [
        ButtonSegment(value: _Mode.sepa, label: Text('SEPA')),
        ButtonSegment(value: _Mode.onchain, label: Text('On-chain')),
      ],
      selected: {_mode},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _mode = s.first),
    );
  }

  Widget _amountPicker(ThemeData theme) {
    final l = AppLocalizations.of(context);
    // Odabrano mjesto ima FIKSNU cijenu — preset čipovi bi lagali da je iznos
    // slobodan izbor. Nadoplata gore ostaje moguća kroz "Ostalo".
    if (_hasSlot) return _slotAmountLock(theme);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final cents in _presetsCents)
          ChoiceChip(
            label: Text('${fmtEur(cents)} €'),
            selected: _amountCents == cents && _customCtrl.text.isEmpty,
            onSelected: (_) {
              _customCtrl.clear();
              setState(() => _amountCents = cents);
            },
          ),
        SizedBox(
          width: 110,
          // e2e/a11y sidro za custom iznos (uz preset ChoiceChip-ove).
          child: Semantics(
            identifier: 'pinka-amount-input',
            child: TextField(
              controller: _customCtrl,
              focusNode: _customFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_eurAmountFormatter],
              decoration: InputDecoration(
                isDense: true,
                suffixText: '€',
                labelText: l.pinkaCustomAmountHint,
                hintText: l.pinkaCustomAmountPlaceholder,
              ),
              onChanged: _setAmountFromCustom,
            ),
          ),
        ),
      ],
    );
  }

  /// Zaključan iznos uz odabrano mjesto: što je odabrano, koliko stoji, kako
  /// odustati — i polje za nadoplatu (iznad cijene je uvijek dopušteno).
  Widget _slotAmountLock(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final cs = theme.colorScheme;
    final price = widget.selectedSlotPriceCents ?? _minCents;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grid_view_rounded, size: 16, color: cs.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.selectedSlotLabel ?? widget.selectedSlotKey!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onClearSlot != null)
                TextButton(
                  onPressed: widget.onClearSlot,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(l.pinkaSlotClear),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.pinkaSlotPriceLocked(fmtEur(price)),
            style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800, color: cs.tertiary),
          ),
          const SizedBox(height: 2),
          Text(
            l.pinkaSlotTopUpHint,
            style:
                theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _customCtrl,
              focusNode: _customFocus,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_eurAmountFormatter],
              decoration: InputDecoration(
                isDense: true,
                suffixText: '€',
                labelText: l.pinkaSlotTopUpLabel,
              ),
              onChanged: _setAmountFromCustom,
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityFields(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final signedIn = (widget.signedInName?.call() ?? '').isNotEmpty;
    final canSignIn = !signedIn && widget.onSignInRequested != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                enabled: !_anonymous,
                maxLength: _nameMax,
                // `labelText` (ne `hintText`): oznaka mora ostati vidljiva i
                // NAKON prvog utipkanog znaka — inače su polja neraspoznatljiva.
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  labelText: l.pinkaNameLabel,
                  helperText: l.pinkaNameHelper,
                  helperMaxLines: 2,
                ),
                onChanged: (_) => setState(() {}), // živi pregled kartice
              ),
            ),
            if (canSignIn) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _anonymous ? null : _signIn,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: theme.colorScheme.tertiary,
                ),
                icon: const Icon(Icons.login, size: 16),
                label: Text(l.commonSignIn),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _linkCtrl,
          enabled: !_anonymous,
          maxLength: _linkMax,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            labelText: l.pinkaLinkLabel,
            helperText: l.pinkaLinkHelper,
            helperMaxLines: 2,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _msgCtrl,
          enabled: !_anonymous,
          maxLength: _msgMax,
          maxLines: 2,
          minLines: 1,
          decoration: InputDecoration(
            isDense: true,
            labelText: l.pinkaMessageLabel,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => setState(() => _anonymous = !_anonymous),
          child: Row(
            children: [
              Checkbox(
                value: _anonymous,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() => _anonymous = v ?? false),
              ),
              Expanded(
                child: Text(
                  l.pinkaAnonymousLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Živi pregled: donator vidi TOČAN ishod (kako će biti potpisan, s kojim
  /// iznosom, porukom i poveznicom) prije nego što plati.
  Widget _previewSection(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final link = _publicLinkUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.pinkaPreviewHeading,
          style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        _ContributionPreviewCard(
          key: const Key('pinka-preview-card'),
          name: _anonymous ? l.pinkaAnonymous : _publicDisplayName,
          namePlaceholder: l.pinkaPreviewNamePlaceholder,
          amountCents: _amountCents,
          message: _anonymous ? null : _msgCtrl.text.trim(),
          messagePlaceholder: l.pinkaPreviewMessagePlaceholder,
          linkHost: link == null ? null : Uri.parse(link).host,
        ),
      ],
    );
  }

  Widget _sepaButton(ThemeData theme, bool creating) {
    final l = AppLocalizations.of(context);
    // e2e/a11y sidro — vidi komentar uz pinka-grid-wall u campaign screenu.
    return Semantics(
      identifier: 'pinka-sepa-submit',
      child: FilledButton.icon(
        onPressed: creating ? null : _submitSepa,
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.tertiary,
          foregroundColor: theme.colorScheme.onTertiary,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: creating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.favorite, size: 18),
        label: Text(creating
            ? l.pinkaPreparing
            : l.pinkaSupportWithAmount(fmtEur(_amountCents))),
      ),
    );
  }

  Widget _onchainSection(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final dest = _c.destinationAddress ?? '';
    final busy = _walletPhase != _WalletPhase.idle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kPinkaWalletSupported) ...[
          FilledButton.icon(
            onPressed: busy ? null : _payFromWallet,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.tertiary,
              foregroundColor: theme.colorScheme.onTertiary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.account_balance_wallet, size: 18),
            label: Text(switch (_walletPhase) {
              _WalletPhase.connecting => l.pinkaWalletConnecting,
              _WalletPhase.sending => l.pinkaWalletOpening,
              _WalletPhase.confirming => l.pinkaWalletConfirming,
              _WalletPhase.idle =>
                l.pinkaPayFromDomovinaWallet(fmtEur(_amountCents)),
            }),
          ),
          if (_walletNote != null) ...[
            const SizedBox(height: 8),
            Text(_walletNote!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(l.pinkaOrScanOtherWallet,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Center(child: _qrBox(widget.config.eip681(dest, _amountCents))),
        const SizedBox(height: 12),
        Text(
          l.pinkaScanWithWallet(fmtEur(_amountCents)),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        PinkaCopyRow(label: l.pinkaRecipient, value: dest),
        // Copy daje adresu ERC-20 ugovora (to MetaMask traži za custom token),
        // prikaz ostaje ljudski čitljiv opis.
        PinkaCopyRow(
            label: l.pinkaToken,
            value: 'EURe · Monerium V2 · Gnosis',
            copyValue: widget.config.eureAddress),
        const SizedBox(height: 8),
        Text(
          l.pinkaOnchainArrivalNote,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildSepaQr(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final intent = _intent!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(l.pinkaScanInBankApp,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(l.pinkaAmountLabel(intent.amountEur),
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 10),
        _qrBox(intent.epcQrData),
        const SizedBox(height: 10),
        PinkaCopyRow(
          label: 'IBAN',
          value: _fmtIban(intent.iban),
          copyValue: _cleanIban(intent.iban),
        ),
        PinkaCopyRow(
            label: l.pinkaRecipient, value: intent.beneficiaryName),
        PinkaCopyRow(
          label: l.pinkaPaymentReference,
          value: intent.memo,
          multiline: true,
        ),
        const SizedBox(height: 12),
        _holdCountdown(theme),
        _sepaProgress(theme),
      ],
    );
  }

  /// Stanje rezervacije ispod QR-a. Hold traje 24 h, pa NE prikazujemo veliki
  /// sat koji tiho odbrojava cijeli dan (samo bi zabrinjavao) — mirna potvrda,
  /// a živi MM:SS tek u zadnjih sat vremena. Uz to smirujuća poruka: SEPA nalog
  /// smije zastati na provjeri kod banke pošiljatelja/primatelja — dovoljno je
  /// da stigne unutar 24 h i backend ga uredno obradi (kasna uplata se i dalje
  /// kreditira, mjesto se vrati ili premjesti).
  Widget _holdCountdown(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final until = _holdExpiresAt;
    if (until == null || !_hasSlot) return const SizedBox.shrink();
    final left = until.difference(DateTime.now());
    final cs = theme.colorScheme;

    if (left.isNegative) {
      return _holdNote(theme, Icons.info_outline,
          title: null, body: l.pinkaSlotHoldExpired);
    }
    final lastHour = left.inMinutes < 60;
    return _holdNote(
      theme,
      Icons.verified_user_outlined,
      title: lastHour
          ? l.pinkaSlotHoldCountdown(_fmtDuration(left))
          : l.pinkaSlotHoldReserved,
      body: l.pinkaSlotHoldReassure,
      titleColor: cs.onSurface,
    );
  }

  Widget _holdNote(
    ThemeData theme,
    IconData icon, {
    required String? title,
    required String body,
    Color? titleColor,
  }) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          if (title != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: titleColor ?? cs.onSurface)),
                ),
              ],
            ),
          if (title != null) const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// Živi timeline SEPA uplate ("Korak M/N") iz rail statusa; dok rail još
  /// nema podataka (ili fetch ne uspije), generički spinner kao prije.
  Widget _sepaProgress(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final s = _intentStatus;
    if (s == null || s.steps.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(l.pinkaAwaitingPayment,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );
    }

    final cs = theme.colorScheme;
    final total = s.steps.length;
    final proven = s.steps.where((st) => st.status == 'proven').length;
    var current = s.steps.indexWhere((st) => st.status != 'proven') + 1;
    if (current == 0) current = total; // sve proven
    final terminalError = s.isRejected || s.isExpired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(l.pinkaStepOf(current, total),
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            if (!terminalError)
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        const SizedBox(height: 8),
        // Progress bar puni SAMO dokazane korake (bez lažnog napretka).
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: proven / total,
            minHeight: 5,
            backgroundColor: cs.surfaceContainerHighest,
            color: terminalError ? cs.error : cs.tertiary,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < s.steps.length; i++)
          _stepRow(
            theme,
            s.steps[i],
            number: i + 1,
            isCurrent: !terminalError && i == current - 1,
            isLast: i == s.steps.length - 1,
          ),
        if (terminalError) ...[
          const SizedBox(height: 8),
          Text(
            s.isRejected
                ? l.pinkaIntentRejected
                : l.pinkaIntentExpired,
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.error),
          ),
        ],
      ],
    );
  }

  Widget _stepRow(
    ThemeData theme,
    PinkaIntentStep step, {
    required int number,
    required bool isCurrent,
    required bool isLast,
  }) {
    final l = AppLocalizations.of(context);
    final cs = theme.colorScheme;
    final (title, custodian) = switch (step.key) {
      'payment' => (
          l.pinkaStepPaymentTitle,
          l.pinkaStepPaymentCustodian
        ),
      'processing' => (
          l.pinkaStepProcessingTitle,
          l.pinkaStepProcessingCustodian
        ),
      'minted' => (
          l.pinkaStepMintedTitle,
          l.pinkaStepMintedCustodian
        ),
      'forwarding' => (
          l.pinkaStepForwardingTitle,
          l.pinkaStepForwardingCustodian
        ),
      _ => (
          l.pinkaStepSettledTitle,
          l.pinkaStepSettledCustodian
        ),
    };
    // "Aktivni" korak = rail kaže in_progress ILI je prvi ne-dokazani (rail u
    // blind windowu drži sve na waiting; iz perspektive donatora korak "tvoja
    // uplata" je tada u tijeku).
    final proven = step.status == 'proven';
    final failed = step.status == 'failed';
    final active = !proven &&
        !failed &&
        (step.status == 'in_progress' || isCurrent);

    // Numerirani krug: dokazano = ispunjen s kvačicom, aktivno = broj sa
    // spinner-prstenom, čeka = obrub s prigušenim brojem.
    const double d = 24;
    final Widget circle;
    if (proven) {
      circle = Container(
        width: d,
        height: d,
        decoration: BoxDecoration(color: cs.tertiary, shape: BoxShape.circle),
        child: Icon(Icons.check, size: 15, color: cs.onTertiary),
      );
    } else if (failed) {
      circle = Container(
        width: d,
        height: d,
        decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle),
        child: Icon(Icons.priority_high, size: 14, color: cs.onError),
      );
    } else if (active) {
      circle = SizedBox(
        width: d,
        height: d,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2, color: cs.tertiary),
            Text('$number',
                style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800, color: cs.tertiary)),
          ],
        ),
      );
    } else {
      circle = Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Center(
          child: Text('$number',
              style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              circle,
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1),
                      color: proven
                          ? cs.tertiary
                          : cs.onSurfaceVariant.withValues(alpha: 0.25),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight:
                            active || proven ? FontWeight.w700 : FontWeight.w500,
                        color: step.status == 'waiting' && !active
                            ? cs.onSurfaceVariant.withValues(alpha: 0.7)
                            : cs.onSurface,
                      )),
                  Text(custodian,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaid(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Icon(Icons.check_circle, color: theme.colorScheme.tertiary, size: 40),
        const SizedBox(height: 10),
        Text(l.pinkaThanksForSupportEmoji,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(l.pinkaPaymentConfirmedOnchain,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          onPressed: _resetForAnother,
          icon: const Icon(Icons.replay, size: 18),
          label: Text(l.pinkaDonateAgain),
        ),
      ],
    );
  }

  /// "Doniraj još jednom": natrag na obrazac za novi intent. Ime i iznos
  /// ostaju (vjerojatno isti donator), poruka se čisti (potrošena na zidu),
  /// odabir mjesta se pušta hostu — to je mjesto sad zauzeto.
  void _resetForAnother() {
    _statusTimer?.cancel();
    _holdTimer?.cancel();
    widget.onClearSlot?.call();
    setState(() {
      _phase = _Phase.idle;
      _walletPhase = _WalletPhase.idle;
      _intent = null;
      _intentStatus = null;
      _holdExpiresAt = null;
      _error = null;
      _walletNote = null;
      _msgCtrl.clear();
    });
  }

  Widget _qrBox(String data) {
    // Kompaktno: 200px + tanka bijela margina — dovoljno za pouzdan sken, a
    // štedi ~50px visine da desni stupac stane u viewport bez scrolla.
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: QrImageView(
        data: data,
        version: QrVersions.auto,
        size: 200,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
      ),
    );
  }
}

/// Pregled kartice zida DOK korisnik tipka. Namjerno vlastiti render, a ne
/// `PinkaWallList` — zid se paralelno prepisuje (staggered mreža); objedinjavanje
/// u jedan widget je upisano kao dug za sljedeći krug.
class _ContributionPreviewCard extends StatelessWidget {
  /// `null` → prigušeni [namePlaceholder] (prazno polje, bez lažnog sadržaja).
  final String? name;
  final String namePlaceholder;
  final int amountCents;
  final String? message;
  final String messagePlaceholder;

  /// Host poveznice ("domovina.ai"), ne cijeli URL — kartica zida ga tako i
  /// pokazuje.
  final String? linkHost;

  const _ContributionPreviewCard({
    super.key,
    required this.name,
    required this.namePlaceholder,
    required this.amountCents,
    required this.message,
    required this.messagePlaceholder,
    required this.linkHost,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasName = name != null && name!.isNotEmpty;
    final hasMessage = message != null && message!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasName ? name! : namePlaceholder,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: hasName ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${fmtEur(amountCents)} €',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: cs.tertiary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasMessage ? message! : messagePlaceholder,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontStyle: hasMessage ? null : FontStyle.italic,
            ),
          ),
          if (linkHost != null && linkHost!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    linkHost!,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Korisnički unos poveznice → `https://…` ili `null` (prazno ILI nevaljano).
/// Bez sheme se dopisuje `https://` (nitko ne tipka shemu), a `http`/ostale
/// sheme se odbijaju — jedina dodatna obrana je `safeUrl` u workeru.
String? _normalizeLink(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final u = Uri.tryParse(t.contains('://') ? t : 'https://$t');
  if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
  // Host bez točke nije domena ("https://moja stranica" → host "moja").
  if (!u.host.contains('.')) return null;
  return u.toString();
}

/// H:MM:SS za holdove duže od sata (SEPA intent živi 24 h), inače MM:SS.
String _fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Dozvoli samo valjani EUR iznos u tipkanju: znamenke + najviše jedan
/// decimalni separator (zarez ili točka) + najviše dvije decimale.
final _eurAmountFormatter = TextInputFormatter.withFunction((oldValue, newValue) {
  if (newValue.text.isEmpty) return newValue;
  return RegExp(r'^\d{1,6}([.,]\d{0,2})?$').hasMatch(newValue.text)
      ? newValue
      : oldValue;
});

/// Rail API zna vratiti IBAN s proizvoljnim razmacima (npr. zadnje dvije
/// znamenke odvojene) — normaliziraj pa grupiraj po 4 za čitljiv prikaz.
String _cleanIban(String iban) => iban.replaceAll(RegExp(r'\s+'), '');

String _fmtIban(String iban) {
  final clean = _cleanIban(iban);
  final sb = StringBuffer();
  for (var i = 0; i < clean.length; i += 4) {
    if (i > 0) sb.write(' ');
    sb.write(clean.substring(i, i + 4 > clean.length ? clean.length : i + 4));
  }
  return sb.toString();
}
