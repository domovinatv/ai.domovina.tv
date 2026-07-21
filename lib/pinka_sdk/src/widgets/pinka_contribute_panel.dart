library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../services/locale_service.dart';
import '../models/pinka_campaign.dart';
import '../models/pinka_contribution_intent.dart';
import '../pinka_client.dart';
import '../pinka_config.dart';
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
  final VoidCallback? onPaid;

  /// Host hook: display-name prijavljenog korisnika ili `null` (gost/anon).
  /// Kad je ne-null, ime donatora se predispuni; kad je null, uz polje se
  /// nudi "Prijavi se" gumb (vidi [onSignInRequested]).
  final String? Function()? signedInName;

  /// Host hook: otvori auth flow aplikacije (auth sheet). Nakon što se
  /// vrati, panel ponovno pročita [signedInName] i predispuni ime.
  final Future<void> Function(BuildContext context)? onSignInRequested;

  const PinkaContributePanel({
    super.key,
    required this.campaign,
    required this.client,
    required this.config,
    this.onPaid,
    this.signedInName,
    this.onSignInRequested,
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

  _Mode _mode = _Mode.sepa;
  _Phase _phase = _Phase.idle;
  _WalletPhase _walletPhase = _WalletPhase.idle;

  int _amountCents = 500;
  final _customCtrl = TextEditingController();
  final _customFocus = FocusNode();
  final _nameCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  bool _anonymous = false;

  String? _error;
  String? _walletNote;
  PinkaContributionIntent? _intent;

  PinkaCampaign get _c => widget.campaign;

  @override
  void initState() {
    super.initState();
    if (_c.minContributionCents > _amountCents) {
      _amountCents = _c.minContributionCents;
    }
    _customFocus.addListener(_onCustomFocus);
    _prefillFromAuth();
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
    _customFocus.dispose();
    _customCtrl.dispose();
    _nameCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  void _setAmountFromCustom(String raw) {
    final c = parseEurToCents(raw);
    if (c != null) setState(() => _amountCents = c);
  }

  // ── SEPA ───────────────────────────────────────────────────────────────
  Future<void> _submitSepa() async {
    if (_amountCents < _c.minContributionCents) {
      setState(() =>
          _error = appStrings.pinkaMinAmount(fmtEur(_c.minContributionCents)));
      return;
    }
    setState(() {
      _phase = _Phase.creating;
      _error = null;
    });
    try {
      final intent = await widget.client.contribute(
        campaignId: _c.id,
        amountCents: _amountCents,
        displayName: _anonymous ? null : _nameCtrl.text,
        message: _anonymous ? null : _msgCtrl.text,
        anonymous: _anonymous,
      );
      if (!mounted) return;
      setState(() {
        _intent = intent;
        _phase = _Phase.awaiting;
      });
      final paid = await widget.client.waitForPaid(intent.contributionId);
      if (!mounted) return;
      if (paid) {
        setState(() => _phase = _Phase.paid);
        widget.onPaid?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = appStrings.pinkaPaymentCreateFailed;
      });
    }
  }

  // ── On-chain (in-app DOMOVINA wallet) ────────────────────────────────────
  Future<void> _payFromWallet() async {
    final dest = _c.destinationAddress;
    if (dest == null) return;
    if (_amountCents < _c.minContributionCents) {
      setState(() =>
          _walletNote = appStrings.pinkaMinAmount(fmtEur(_c.minContributionCents)));
      return;
    }
    setState(() {
      _walletNote = null;
      _walletPhase = _WalletPhase.connecting;
    });
    try {
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
        final r = await widget.client
            .confirmOnchain(campaignId: _c.id, txHash: txHash);
        if (r.reverted) throw StateError('reverted');
        if (r.isCredited) {
          if (!mounted) return;
          setState(() => _phase = _Phase.paid);
          widget.onPaid?.call();
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
      padding: const EdgeInsets.all(18),
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
              child: Text(appStrings.pinkaSupport,
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
          onchain ? appStrings.pinkaOnchainBlurb : appStrings.pinkaSepaBlurb,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _amountPicker(theme),
        if (!onchain) ...[
          const SizedBox(height: 12),
          _identityFields(theme),
        ],
        if (_error != null && !onchain) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
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
          child: TextField(
            controller: _customCtrl,
            focusNode: _customFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_eurAmountFormatter],
            decoration: InputDecoration(
              isDense: true,
              suffixText: '€',
              labelText: appStrings.pinkaCustomAmountHint,
              hintText: appStrings.pinkaCustomAmountPlaceholder,
            ),
            onChanged: _setAmountFromCustom,
          ),
        ),
      ],
    );
  }

  Widget _identityFields(ThemeData theme) {
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
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: appStrings.pinkaNameHint,
                ),
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
                label: Text(appStrings.commonSignIn),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _msgCtrl,
          enabled: !_anonymous,
          maxLength: _msgMax,
          maxLines: 2,
          minLines: 1,
          decoration: InputDecoration(
            isDense: true,
            hintText: appStrings.pinkaMessageHint,
          ),
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
                  appStrings.pinkaAnonymousLabel,
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

  Widget _sepaButton(ThemeData theme, bool creating) {
    return FilledButton.icon(
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
              child:
                  CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : const Icon(Icons.favorite, size: 18),
      label: Text(creating
          ? appStrings.pinkaPreparing
          : appStrings.pinkaSupportWithAmount(fmtEur(_amountCents))),
    );
  }

  Widget _onchainSection(ThemeData theme) {
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
              _WalletPhase.connecting => appStrings.pinkaWalletConnecting,
              _WalletPhase.sending => appStrings.pinkaWalletOpening,
              _WalletPhase.confirming => appStrings.pinkaWalletConfirming,
              _WalletPhase.idle =>
                appStrings.pinkaPayFromDomovinaWallet(fmtEur(_amountCents)),
            }),
          ),
          if (_walletNote != null) ...[
            const SizedBox(height: 8),
            Text(_walletNote!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(appStrings.pinkaOrScanOtherWallet,
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
          appStrings.pinkaScanWithWallet(fmtEur(_amountCents)),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        PinkaCopyRow(label: appStrings.pinkaRecipient, value: dest),
        // Copy daje adresu ERC-20 ugovora (to MetaMask traži za custom token),
        // prikaz ostaje ljudski čitljiv opis.
        PinkaCopyRow(
            label: appStrings.pinkaToken,
            value: 'EURe · Monerium V2 · Gnosis',
            copyValue: widget.config.eureAddress),
        const SizedBox(height: 8),
        Text(
          appStrings.pinkaOnchainArrivalNote,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildSepaQr(ThemeData theme) {
    final intent = _intent!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(appStrings.pinkaScanInBankApp,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(appStrings.pinkaAmountLabel(intent.amountEur),
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 14),
        _qrBox(intent.epcQrData),
        const SizedBox(height: 14),
        PinkaCopyRow(
          label: 'IBAN',
          value: _fmtIban(intent.iban),
          copyValue: _cleanIban(intent.iban),
        ),
        PinkaCopyRow(
            label: appStrings.pinkaRecipient, value: intent.beneficiaryName),
        PinkaCopyRow(
          label: appStrings.pinkaPaymentReference,
          value: intent.memo,
          multiline: true,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(appStrings.pinkaAwaitingPayment,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }

  Widget _buildPaid(ThemeData theme) {
    return Column(
      children: [
        Icon(Icons.check_circle, color: theme.colorScheme.tertiary, size: 40),
        const SizedBox(height: 10),
        Text(appStrings.pinkaThanksForSupportEmoji,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(appStrings.pinkaPaymentConfirmedOnchain,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _qrBox(String data) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: QrImageView(
        data: data,
        version: QrVersions.auto,
        size: 240,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
      ),
    );
  }
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
