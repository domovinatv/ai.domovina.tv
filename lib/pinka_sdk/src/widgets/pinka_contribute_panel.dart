library;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

  const PinkaContributePanel({
    super.key,
    required this.campaign,
    required this.client,
    required this.config,
    this.onPaid,
  });

  @override
  State<PinkaContributePanel> createState() => _PinkaContributePanelState();
}

enum _Mode { sepa, onchain }

enum _Phase { idle, creating, awaiting, paid }

enum _WalletPhase { idle, sending, confirming }

class _PinkaContributePanelState extends State<PinkaContributePanel> {
  static const _presetsCents = [200, 500, 1000, 2000];
  static const _nameMax = 60;
  static const _msgMax = 280;

  _Mode _mode = _Mode.sepa;
  _Phase _phase = _Phase.idle;
  _WalletPhase _walletPhase = _WalletPhase.idle;

  int _amountCents = 500;
  final _customCtrl = TextEditingController();
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
  }

  @override
  void dispose() {
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
          _error = 'Najmanji iznos je ${fmtEur(_c.minContributionCents)} €');
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
        _error = 'Neuspjelo kreiranje uplate. Pokušaj ponovno.';
      });
    }
  }

  // ── On-chain (in-app DOMOVINA wallet) ────────────────────────────────────
  Future<void> _payFromWallet() async {
    final dest = _c.destinationAddress;
    if (dest == null) return;
    if (_amountCents < _c.minContributionCents) {
      setState(() =>
          _walletNote = 'Najmanji iznos je ${fmtEur(_c.minContributionCents)} €');
      return;
    }
    setState(() {
      _walletNote = null;
      _walletPhase = _WalletPhase.sending;
    });
    try {
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
        _walletNote =
            'Uplata poslana — pojavit će se na zidu čim se potvrdi na lancu.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _walletPhase = _WalletPhase.idle;
        _walletNote = 'Slanje iz novčanika nije uspjelo ili je otkazano.';
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
              child: Text('Podrži',
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
          onchain
              ? 'Pošalji EURe (Gnosis) izravno na lanac — transparentno i bez posrednika.'
              : 'Doniraj jednim skenom — SEPA, bez naknade. Sredstva idu izravno autoru.',
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              suffixText: '€',
              hintText: 'Ostalo',
            ),
            onChanged: _setAmountFromCustom,
          ),
        ),
      ],
    );
  }

  Widget _identityFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameCtrl,
          enabled: !_anonymous,
          maxLength: _nameMax,
          decoration: const InputDecoration(
            isDense: true,
            counterText: '',
            hintText: 'Ime ili nadimak (opcionalno)',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _msgCtrl,
          enabled: !_anonymous,
          maxLength: _msgMax,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Poruka uz podršku (opcionalno)',
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
                  'Doniraj anonimno (ne prikazuj me na zidu podrške)',
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
      label: Text(
          creating ? 'Pripremam…' : 'Podrži s ${fmtEur(_amountCents)} €'),
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
              _WalletPhase.sending => 'Otvaram novčanik…',
              _WalletPhase.confirming => 'Potvrđujem na lancu…',
              _WalletPhase.idle =>
                'Plati ${fmtEur(_amountCents)} € iz DOMOVINA novčanika',
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
                child: Text('ili skeniraj drugim novčanikom',
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
          'Skeniraj novčanikom (MetaMask / Monerium) i pošalji '
          '${fmtEur(_amountCents)} € u EURe.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        PinkaCopyRow(label: 'Primatelj', value: dest),
        const PinkaCopyRow(
            label: 'Token', value: 'EURe · Monerium V2 · Gnosis'),
        const SizedBox(height: 8),
        Text(
          'Donacija se pojavi na zidu podrške kad stigne na lanac (~1–2 min).',
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
        Text('Skeniraj u svojoj bankovnoj aplikaciji',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Iznos: ${intent.amountEur} €',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 14),
        _qrBox(intent.epcQrData),
        const SizedBox(height: 14),
        PinkaCopyRow(label: 'IBAN', value: intent.iban),
        PinkaCopyRow(label: 'Primatelj', value: intent.beneficiaryName),
        PinkaCopyRow(label: 'Opis plaćanja', value: intent.memo),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Čekam potvrdu plaćanja…',
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
        Text('Hvala na podršci! 🙏',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Plaćanje je potvrđeno na lancu.',
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
