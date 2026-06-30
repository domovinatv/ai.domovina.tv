import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/pinka.dart';
import '../services/locale_service.dart';
import '../services/pinka_service.dart';

/// "Podrži ovu epizodu" panel za pinka.finance. Samostalno se sakrije ako
/// epizoda nema aktivnu kampanju, pa je sigurno ubaciti na svaki episode screen.
class SupportEpisodePanel extends StatefulWidget {
  final String youtubeId;
  final String episodeTitle;

  const SupportEpisodePanel({
    super.key,
    required this.youtubeId,
    required this.episodeTitle,
  });

  @override
  State<SupportEpisodePanel> createState() => _SupportEpisodePanelState();
}

enum _Phase { loading, none, idle, creating, awaiting, paid }

class _SupportEpisodePanelState extends State<SupportEpisodePanel> {
  _Phase _phase = _Phase.loading;
  PinkaCampaign? _campaign;
  PinkaContribution? _contribution;
  String? _error;

  int _amountCents = 500; // default 5 €
  final _customCtrl = TextEditingController();

  static const _presetsCents = [200, 500, 1000, 2000];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await PinkaService.instance.campaignForEpisode(widget.youtubeId);
    if (!mounted) return;
    setState(() {
      _campaign = c;
      _phase = c == null ? _Phase.none : _Phase.idle;
      _amountCents = (c != null && c.minContributionCents > _amountCents)
          ? c.minContributionCents
          : _amountCents;
    });
  }

  void _setAmountFromCustom(String raw) {
    final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (parsed != null && parsed > 0) {
      setState(() => _amountCents = (parsed * 100).round());
    }
  }

  Future<void> _submit() async {
    final c = _campaign;
    if (c == null) return;
    if (_amountCents < c.minContributionCents) {
      setState(() =>
          _error = appStrings.mediaMinAmount(_fmtEur(c.minContributionCents)));
      return;
    }
    setState(() {
      _phase = _Phase.creating;
      _error = null;
    });
    try {
      final contrib = await PinkaService.instance.contribute(
        campaignId: c.id,
        amountCents: _amountCents,
      );
      if (!mounted) return;
      setState(() {
        _contribution = contrib;
        _phase = _Phase.awaiting;
      });
      // Polling u pozadini — kad rail potvrdi plaćanje, panel pokaže "Hvala".
      final paid =
          await PinkaService.instance.waitForPaid(contrib.contributionId);
      if (!mounted) return;
      if (paid) setState(() => _phase = _Phase.paid);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = appStrings.mediaPaymentCreateFailed;
      });
    }
  }

  static String _fmtEur(int cents) {
    final eur = cents / 100;
    return eur.toStringAsFixed(eur.truncateToDouble() == eur ? 0 : 2)
        .replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.loading || _phase == _Phase.none) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: switch (_phase) {
          _Phase.awaiting => _buildQr(theme),
          _Phase.paid => _buildPaid(theme),
          _ => _buildIdle(theme),
        },
      ),
    );
  }

  Widget _buildIdle(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final c = _campaign!;
    final creating = _phase == _Phase.creating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.volunteer_activism,
                color: theme.colorScheme.tertiary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l.mediaSupportEpisode,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l.mediaSupportBlurb,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (c.hasGoal) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: c.progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: theme.colorScheme.tertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l.mediaRaisedProgress(
              _fmtEur(c.totalRaisedCents),
              _fmtEur(c.goalCents!),
              c.contributorCount,
            ),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cents in _presetsCents)
              ChoiceChip(
                label: Text('${_fmtEur(cents)} €'),
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: '€',
                  hintText: l.mediaOtherAmount,
                ),
                onChanged: _setAmountFromCustom,
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: creating ? null : _submit,
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
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.favorite, size: 18),
          label: Text(creating
              ? l.mediaPreparing
              : l.mediaSupportWithAmount(_fmtEur(_amountCents))),
        ),
      ],
    );
  }

  Widget _buildQr(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final contrib = _contribution!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(l.mediaScanInBankApp,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(l.mediaAmountValue(contrib.amountEur),
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: contrib.epcQrData,
            version: QrVersions.auto,
            size: 220,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 14),
        _copyRow(theme, 'IBAN', contrib.iban),
        _copyRow(theme, l.mediaRecipient, contrib.beneficiaryName),
        _copyRow(theme, l.mediaPaymentReference, contrib.memo),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(l.mediaAwaitingPayment,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }

  Widget _buildPaid(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Icon(Icons.check_circle, color: theme.colorScheme.tertiary, size: 40),
        const SizedBox(height: 10),
        Text('${l.commonThanksForSupport} 🙏',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(l.mediaPaymentConfirmedOnChain,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _copyRow(ThemeData theme, String label, String value) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 16),
            tooltip: l.commonCopy,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.mediaCopiedLabel(label)),
                    duration: const Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
    );
  }
}
