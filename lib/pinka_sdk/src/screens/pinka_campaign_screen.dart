library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../services/locale_service.dart';
import '../models/pinka_campaign.dart';
import '../models/pinka_public_contribution.dart';
import '../models/pinka_yield_position.dart';
import '../pinka_client.dart';
import '../pinka_config.dart';
import '../util/pinka_money.dart';
import '../widgets/pinka_common.dart';
import '../widgets/pinka_contribute_panel.dart';
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

class _PinkaCampaignScreenState extends State<PinkaCampaignScreen> {
  PinkaCampaign? _campaign;
  bool _loading = true;
  List<PinkaPublicContribution> _wall = const [];
  PinkaYieldPosition? _yield;
  Set<String> _flashIds = {};
  final Set<String> _seen = {};
  bool _firstLoad = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer =
        Timer.periodic(const Duration(seconds: 12), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    if (!mounted) return;
    setState(() {
      _campaign = c;
      _loading = false;
      _wall = list;
      _yield = yield_;
    });
    if (_firstLoad) {
      _seen.addAll(list.map((e) => e.id));
      _firstLoad = false;
      return;
    }
    final fresh = list.where((e) => !_seen.contains(e.id)).map((e) => e.id).toSet();
    if (fresh.isNotEmpty) {
      _seen.addAll(fresh);
      setState(() => _flashIds = fresh);
      Future.delayed(const Duration(milliseconds: 2400), () {
        if (mounted) setState(() => _flashIds = {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        title: Text(
            _campaign?.title ?? widget.fallbackTitle ?? appStrings.pinkaWallTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _campaign == null
              ? _empty(theme)
              : _content(theme, _campaign!),
    );
  }

  Widget _empty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          appStrings.pinkaNoCampaign,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _content(ThemeData theme, PinkaCampaign c) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final stats = _statsCard(theme, c);
        final panel = PinkaContributePanel(
          campaign: c,
          client: widget.client,
          config: widget.config,
          onPaid: _refresh,
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
                const SizedBox(height: 12),
                panel,
                if (verify != null) ...[
                  const SizedBox(height: 12),
                  verify,
                ],
                const SizedBox(height: 24),
                main,
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              const SizedBox(width: 32),
              SizedBox(
                width: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    stats,
                    const SizedBox(height: 12),
                    panel,
                    if (verify != null) ...[
                      const SizedBox(height: 12),
                      verify,
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _mainColumn(ThemeData theme, PinkaCampaign c) {
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
        Text(c.title,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (c.description != null && c.description!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(c.description!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurface)),
        ],
        const SizedBox(height: 24),
        Text(appStrings.pinkaWallTitle,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (_wall.isEmpty)
          Text(appStrings.pinkaWallEmpty,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else
          PinkaWallList(contributions: _wall, flashIds: _flashIds),
      ],
    );
  }

  Widget _statsCard(ThemeData theme, PinkaCampaign c) {
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
          Text('${fmtEur(c.totalRaisedCents)} €',
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (c.hasGoal) ...[
            const SizedBox(height: 4),
            Text(appStrings.pinkaOfGoal(fmtEur(c.goalCents!)),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
            Text(appStrings.pinkaRaisedLabel,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          Text(
            '${appStrings.pinkaSupportersCount(c.contributorCount)}'
            ' · ${appStrings.pinkaPaymentsCount(c.contributionCount)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _verifyCard(ThemeData theme, PinkaCampaign c) {
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
          Text(appStrings.pinkaVerifyOnchainTitle,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            appStrings.pinkaVerifyOnchainBody,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                alignment: Alignment.centerLeft),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(appStrings.pinkaEureBalanceOnGnosisscan),
            onPressed: () => pinkaLaunch(widget.config.tokenBalanceUrl(dest)),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                alignment: Alignment.centerLeft),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(appStrings.pinkaInflowHistory),
            onPressed: () => pinkaLaunch(widget.config.tokenTxnsUrl(dest)),
          ),
          const SizedBox(height: 6),
          SelectableText(
            dest,
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_yield != null && _yield!.isDeployed) _aaveSection(theme, dest),
        ],
      ),
    );
  }

  /// Kad su sredstva parkirana na Aaveu, EURe saldo na Safeu je nizak (drže se
  /// kao aGnoEURe) — pokaži poziciju da donori vide da novac "radi", ne da je nestao.
  Widget _aaveSection(ThemeData theme, String dest) {
    final y = _yield!;
    final inAave = y.lastBalanceCents > 0 ? y.lastBalanceCents : y.principalCents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Divider(color: theme.colorScheme.outlineVariant, height: 1),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.savings_outlined,
                size: 16, color: theme.colorScheme.tertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(appStrings.pinkaFundsWorkingAave,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${appStrings.pinkaInAaveLabel(fmtEur(inAave))}'
          '${y.accruedYieldCents > 0 ? ' · ${appStrings.pinkaAaveYieldLabel(fmtEur(y.accruedYieldCents))}' : ''}. '
          '${appStrings.pinkaAaveExplainer}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (y.atokenAddress != null)
          TextButton.icon(
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                alignment: Alignment.centerLeft),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(appStrings.pinkaAgnoEureBalanceOnGnosisscan),
            onPressed: () => pinkaLaunch(
                widget.config.tokenForAddressUrl(y.atokenAddress!, dest)),
          ),
      ],
    );
  }
}
