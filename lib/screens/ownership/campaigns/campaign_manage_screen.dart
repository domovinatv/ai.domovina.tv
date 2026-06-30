import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/channel_detail.dart';
import '../../../models/channel_index.dart';
import '../../../models/owner_wallet.dart';
import '../../../pinka_sdk/pinka_sdk.dart';
import '../../../services/auth_service.dart';
import '../../../services/data_service.dart';
import '../../../services/locale_service.dart';
import '../../../services/wallet_service.dart';
import 'episode_picker.dart';

/// Upravljanje jednom kampanjom (Faza A): uredi tekst/cilj, mijenjaj
/// state/visibility, dodijeli epizode, vidi statistiku + zid.
class CampaignManageScreen extends StatefulWidget {
  final String youtubeChannelId; // UC… (za resolve epizoda)
  final String campaignId;

  const CampaignManageScreen({
    super.key,
    required this.youtubeChannelId,
    required this.campaignId,
  });

  @override
  State<CampaignManageScreen> createState() => _CampaignManageScreenState();
}

class _CampaignManageScreenState extends State<CampaignManageScreen> {
  final _admin = PinkaAdminClient.instance;
  bool _loading = true;
  PinkaOwnerCampaign? _campaign;
  List<ChannelVideo> _videos = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final campaign = await _admin.getCampaign(widget.campaignId);
    final videos = await _resolveVideos(widget.youtubeChannelId);
    if (!mounted) return;
    setState(() {
      _campaign = campaign;
      _videos = videos;
      _loading = false;
    });
  }

  /// UC id → interni channel id (preko index.json) → ChannelDetail.videos.
  Future<List<ChannelVideo>> _resolveVideos(String ucId) async {
    try {
      final index = await ChannelService.loadIndex();
      ChannelSummary? match;
      for (final s in index.channels) {
        if (s.youtubeChannelId == ucId) {
          match = s;
          break;
        }
      }
      if (match == null) return const [];
      final detail = await ChannelService.loadChannel(match.id);
      return detail.videos;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = _campaign;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(c?.title ?? l.ownershipCampaignFallback),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l.ownershipTabEdit),
              Tab(text: l.ownershipTabEpisodes),
              Tab(text: l.ownershipTabStats),
              Tab(text: l.ownershipTabPayout),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : c == null
                ? Center(child: Text(l.ownershipCampaignNotFound))
                : TabBarView(
                    children: [
                      _EditTab(campaign: c, admin: _admin, onSaved: _load),
                      EpisodePicker(
                        videos: _videos,
                        initialSelected: {...c.episodeRefs},
                        onSave: (sel) =>
                            _admin.setCampaignEpisodes(c.id, sel.toList()),
                      ),
                      _StatsTab(campaign: c),
                      _PayoutTab(campaign: c, admin: _admin),
                    ],
                  ),
      ),
    );
  }
}

// ─── Uredi tab ──────────────────────────────────────────────────────────────
class _EditTab extends StatefulWidget {
  final PinkaOwnerCampaign campaign;
  final PinkaAdminClient admin;
  final VoidCallback onSaved;

  const _EditTab(
      {required this.campaign, required this.admin, required this.onSaved});

  @override
  State<_EditTab> createState() => _EditTabState();
}

class _EditTabState extends State<_EditTab> {
  late final _title = TextEditingController(text: widget.campaign.title);
  late final _desc =
      TextEditingController(text: widget.campaign.description ?? '');
  late final _goal = TextEditingController(
      text: widget.campaign.goalCents != null
          ? (widget.campaign.goalCents! / 100).toStringAsFixed(0)
          : '');
  late final _minc = TextEditingController(
      text: (widget.campaign.minContributionCents / 100).toStringAsFixed(0));
  late String _state = widget.campaign.state;
  late String _visibility = widget.campaign.visibility;
  bool _saving = false;

  static const _states = ['draft', 'active', 'closed', 'cancelled'];
  static const _vis = ['private', 'unlisted', 'public'];

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _goal.dispose();
    _minc.dispose();
    super.dispose();
  }

  int? _eurToCents(String raw) {
    final n = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (n == null || n <= 0) return null;
    return (n * 100).round();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.admin.updateCampaign(
        widget.campaign.id,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        goalCents: _eurToCents(_goal.text),
        minContributionCents: _eurToCents(_minc.text),
      );
      if (_state != widget.campaign.state) {
        await widget.admin.setState(widget.campaign.id, _state);
      }
      if (_visibility != widget.campaign.visibility) {
        await widget.admin.setVisibility(widget.campaign.id, _visibility);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).ownershipSaved)),
      );
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context).ownershipSaveFailed)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _title,
          decoration: InputDecoration(labelText: l.ownershipFieldTitle),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _desc,
          maxLines: 4,
          minLines: 2,
          decoration: InputDecoration(labelText: l.ownershipFieldDescription),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _goal,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: l.ownershipFieldGoal,
                    hintText: l.ownershipFieldGoalHint),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _minc,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: l.ownershipFieldMinAmount),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _state,
          decoration: InputDecoration(labelText: l.ownershipFieldState),
          items: [
            for (final s in _states)
              DropdownMenuItem(value: s, child: Text(_stateLabel(s))),
          ],
          onChanged: (v) => setState(() => _state = v ?? _state),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _visibility,
          decoration: InputDecoration(labelText: l.ownershipFieldVisibility),
          items: [
            for (final v in _vis)
              DropdownMenuItem(value: v, child: Text(_visLabel(v))),
          ],
          onChanged: (v) => setState(() => _visibility = v ?? _visibility),
        ),
        const SizedBox(height: 8),
        Text(
          l.ownershipEditNote,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
          label: Text(l.ownershipSaveChanges),
        ),
      ],
    );
  }

  static String _stateLabel(String s) => switch (s) {
        'draft' => appStrings.ownershipStateDraft,
        'active' => appStrings.ownershipStateActive,
        'closed' => appStrings.ownershipStateClosed,
        'cancelled' => appStrings.ownershipStateCancelled,
        _ => s,
      };
  static String _visLabel(String v) => switch (v) {
        'public' => appStrings.ownershipVisPublic,
        'unlisted' => appStrings.ownershipVisUnlisted,
        'private' => appStrings.ownershipVisPrivate,
        _ => v,
      };
}

// ─── Statistika tab ───────────────────────────────────────────────────────
class _StatsTab extends StatefulWidget {
  final PinkaOwnerCampaign campaign;
  const _StatsTab({required this.campaign});

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  List<PinkaPublicContribution> _wall = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wall = await PinkaClient.instance.wall(widget.campaign.id);
    if (!mounted) return;
    setState(() {
      _wall = wall;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = widget.campaign;
    final raised = (c.totalRaisedCents / 100);
    final raisedStr = raised == raised.truncateToDouble()
        ? raised.toStringAsFixed(0)
        : raised.toStringAsFixed(2);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('$raisedStr €',
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (c.hasGoal)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: c.progress,
                minHeight: 8,
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          l.ownershipSupportersContributions(
              c.contributorCount, c.contributionCount),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Text(l.ownershipSupportWall,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator()))
        else if (_wall.isEmpty)
          Text(l.ownershipNoPublicContributions,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else
          PinkaWallList(contributions: _wall),
      ],
    );
  }
}

// ─── Isplata tab ────────────────────────────────────────────────────────────
class _PayoutTab extends StatefulWidget {
  final PinkaOwnerCampaign campaign;
  final PinkaAdminClient admin;
  const _PayoutTab({required this.campaign, required this.admin});

  @override
  State<_PayoutTab> createState() => _PayoutTabState();
}

class _PayoutTabState extends State<_PayoutTab> {
  bool _loading = true;
  bool _submitting = false;
  List<PinkaPayout> _payouts = const [];
  List<OwnerWallet> _wallets = const [];
  final _destCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String? _error;

  late bool _yieldEnabled = widget.campaign.yieldEnabled;
  bool _yieldBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _destCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final payouts = await widget.admin.listPayouts(widget.campaign.id);
    final wallets = await WalletService.instance.myWallets();
    if (!mounted) return;
    setState(() {
      _payouts = payouts;
      _wallets = wallets;
      if (_destCtrl.text.isEmpty && wallets.isNotEmpty) {
        _destCtrl.text = wallets.first.address;
      }
      _loading = false;
    });
  }

  int? _eurToCents(String raw) {
    final n = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (n == null || n <= 0) return null;
    return (n * 100).round();
  }

  Future<void> _submit(int availableCents) async {
    setState(() => _error = null);
    final cents = _eurToCents(_amountCtrl.text);
    if (cents == null) {
      setState(() => _error = appStrings.ownershipEnterValidAmount);
      return;
    }
    if (cents > availableCents) {
      setState(() => _error = appStrings.ownershipAmountExceedsAvailable);
      return;
    }
    if (_destCtrl.text.trim().isEmpty) {
      setState(() => _error = appStrings.ownershipEnterDestination);
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.admin.requestPayout(
        campaignId: widget.campaign.id,
        destination: _destCtrl.text.trim(),
        amountCents: cents,
      );
      if (!mounted) return;
      _amountCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.ownershipPayoutRequestSent)),
      );
      await _load();
    } on PinkaFailure catch (f) {
      if (!mounted) return;
      setState(() => _error = _mapErr(f.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = appStrings.ownershipRequestFailedRetry);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static String _mapErr(String code) => switch (code) {
        'kyc_required' => appStrings.ownershipErrKycRequired,
        'invalid_destination' => appStrings.ownershipErrInvalidDestination,
        'amount_exceeds_available' =>
          appStrings.ownershipAmountExceedsAvailable,
        'invalid_amount' => appStrings.ownershipErrInvalidAmount,
        'not_authorized' => appStrings.ownershipErrNotAuthorized,
        _ => appStrings.ownershipErrRequestFailed,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final summary = PinkaPayoutSummary.from(
      widget.campaign.totalRaisedCents,
      _payouts,
      accruedYieldCents: widget.campaign.accruedYieldCents,
    );
    final kyc = AuthService.instance.currentUser?.isVerified ?? false;
    final canRequest = kyc && summary.availableCents > 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _summaryCard(theme, summary),
        const SizedBox(height: 16),
        _yieldCard(theme),
        const SizedBox(height: 16),
        if (!kyc)
          Card(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l.ownershipPayoutNeedsKyc),
            ),
          ),
        if (kyc) ...[
          Text(l.ownershipRequestPayout,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _destCtrl,
            decoration: InputDecoration(
              labelText: l.ownershipDestinationLabel,
              isDense: true,
            ),
          ),
          if (_wallets.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final w in _wallets)
                  ActionChip(
                    label: Text(_short(w.address)),
                    onPressed: () => setState(() => _destCtrl.text = w.address),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l.ownershipAmountLabel,
              isDense: true,
              helperText: l.ownershipAvailableHelper(_eur(summary.availableCents)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed:
                (!canRequest || _submitting) ? null : () => _submit(summary.availableCents),
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.payments_outlined),
            label: Text(l.ownershipRequestPayout),
          ),
        ],
        const SizedBox(height: 24),
        Text(l.ownershipPayoutHistory,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_payouts.isEmpty)
          Text(l.ownershipNoPayouts,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else
          ..._payouts.map((p) => _payoutTile(theme, p)),
      ],
    );
  }

  Future<void> _toggleYield(bool on) async {
    setState(() {
      _yieldEnabled = on;
      _yieldBusy = true;
    });
    try {
      await widget.admin.setCampaignYield(widget.campaign.id, on);
    } catch (_) {
      if (!mounted) return;
      setState(() => _yieldEnabled = !on); // revert
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appStrings.ownershipChangeFailed)),
      );
    } finally {
      if (mounted) setState(() => _yieldBusy = false);
    }
  }

  Widget _yieldCard(ThemeData theme) {
    final c = widget.campaign;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: _yieldEnabled,
            onChanged: _yieldBusy ? null : _toggleYield,
            secondary: Icon(Icons.savings_outlined,
                color: theme.colorScheme.tertiary),
            title: Text(appStrings.ownershipYieldTitle),
            subtitle: Text(
              appStrings.ownershipYieldSubtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            isThreeLine: true,
          ),
          if (_yieldEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv(theme, appStrings.ownershipYieldInPool,
                      '${_eur(c.principalCents)} €'),
                  _kv(theme, appStrings.ownershipYieldAccrued,
                      '${_eur(c.accruedYieldCents)} €'),
                  if (c.yieldLastSyncedAt != null)
                    Text(
                        appStrings.ownershipYieldLastSync(
                            '${c.yieldLastSyncedAt}'),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  if (c.yieldAtokenAddress != null &&
                      c.destinationAddress != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            alignment: Alignment.centerLeft),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(appStrings.ownershipYieldTokenLink),
                        onPressed: () => pinkaLaunch(
                          widget.admin.config.tokenForAddressUrl(
                            c.yieldAtokenAddress!,
                            c.destinationAddress!,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: theme.textTheme.bodySmall),
            Text(v, style: theme.textTheme.bodySmall),
          ],
        ),
      );

  Widget _summaryCard(ThemeData theme, PinkaPayoutSummary s) {
    Widget row(String label, int cents, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text('${_eur(cents)} €',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          row(appStrings.ownershipSummaryRaised, s.raisedCents),
          if (s.accruedYieldCents > 0)
            row(appStrings.ownershipSummaryYield, s.accruedYieldCents),
          row(appStrings.ownershipSummaryPending, s.pendingCents),
          row(appStrings.ownershipSummaryPaid, s.paidCents),
          const Divider(),
          row(appStrings.ownershipSummaryAvailable, s.availableCents,
              bold: true),
        ],
      ),
    );
  }

  Widget _payoutTile(ThemeData theme, PinkaPayout p) {
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(p.isOnchain
            ? Icons.account_balance_wallet_outlined
            : Icons.account_balance_outlined),
        title: Text('${_eur(p.amountCents)} € → ${_short(p.destination)}'),
        subtitle: Text(_stateLabel(p.state)),
        trailing: p.txHash != null
            ? const Icon(Icons.open_in_new, size: 16)
            : null,
        onTap: p.txHash != null
            ? () => pinkaLaunch(
                'https://gnosisscan.io/tx/${p.txHash}')
            : null,
      ),
    );
  }

  static String _eur(int cents) {
    final eur = cents / 100;
    return eur.toStringAsFixed(eur.truncateToDouble() == eur ? 0 : 2)
        .replaceAll('.', ',');
  }

  static String _short(String a) => a.startsWith('0x') && a.length > 12
      ? '${a.substring(0, 6)}…${a.substring(a.length - 4)}'
      : a;

  static String _stateLabel(String s) => switch (s) {
        'requested' => appStrings.ownershipPayoutStateRequested,
        'approved' => appStrings.ownershipPayoutStateApproved,
        'submitted' => appStrings.ownershipSummaryPending,
        'confirmed' => appStrings.ownershipSummaryPaid,
        'failed' => appStrings.ownershipPayoutStateFailed,
        _ => s,
      };
}
