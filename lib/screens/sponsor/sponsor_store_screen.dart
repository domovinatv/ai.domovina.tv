import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart' show log;
import '../../models/channel_detail.dart';
import '../../models/sponsor_offer.dart';
import '../../models/sponsor_topic.dart';
import '../../pinka_sdk/pinka_sdk.dart' show fmtEur;
import '../../router/nav.dart';
import '../../services/cdn_config.dart';
import '../../services/channel_cache.dart';
import '../../services/sponsored_moments_service.dart';
import '../../widgets/cached_thumbnail.dart';
import '../../widgets/sponsor_timeline_bar.dart';

/// Izlog sponzorskih trenutaka kanala — `/c/:slug/oglasi`.
///
/// Popis epizoda s ponudom: oznaka teme, stvarne teme, broj slobodnih
/// trenutaka, najniža cijena i mini traka. Tap vodi na kartu epizode
/// (`/v/:id/sponzoriraj`) kroz [drillDown].
///
/// Plan §3: nijedna epizoda nije isključena iz ponude. Sigurnost branda bira
/// kupac filtrom „Ne prikazuj me uz…" — filtar samo sakriva epizode u ovom
/// pregledu, ne mijenja ponudu.
class SponsorStoreScreen extends StatefulWidget {
  final String channelId;

  const SponsorStoreScreen({super.key, required this.channelId});

  @override
  State<SponsorStoreScreen> createState() => _SponsorStoreScreenState();
}

typedef _Episode = ({
  ChannelVideo video,
  List<SponsorOffer> offers,
  Set<SponsorTopic> topics,
});

class _SponsorStoreScreenState extends State<SponsorStoreScreen> {
  late final SponsorCampaign? _campaign = SponsorCampaign.forChannel(
    widget.channelId,
  );
  Future<(ChannelDetail, List<_Episode>)>? _future;
  final Set<SponsorTopic> _avoid = {};

  @override
  void initState() {
    super.initState();
    if (_campaign != null) _future = _load(_campaign);
  }

  Future<(ChannelDetail, List<_Episode>)> _load(SponsorCampaign c) async {
    final results = await Future.wait([
      channelCache.loadChannel(c.channelId),
      SponsoredMomentsService.instance.loadOffers(c),
    ]);
    final detail = results[0] as ChannelDetail;
    final offers = results[1] as List<SponsorOffer>;
    final byVideo = <String, List<SponsorOffer>>{};
    for (final o in offers) {
      (byVideo[o.youtubeId] ??= []).add(o);
    }
    final episodes = <_Episode>[
      for (final v in detail.videos)
        if (byVideo[v.id] != null)
          (
            video: v,
            offers: byVideo[v.id]!,
            topics: SponsorTopic.classify(
              topics: v.topics,
              title: v.displayTitle,
            ),
          ),
    ];
    log('SponsorStore: ${episodes.length} episodes, ${offers.length} moments');
    return (detail, episodes);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => back(
            context,
            fallback: '/c/${widget.channelId.replaceAll('_', '-')}',
          ),
        ),
        title: Text(l.sponsorMapTitle),
      ),
      body: _campaign == null
          ? _Message(text: l.sponsorStoreEmpty)
          : FutureBuilder<(ChannelDetail, List<_Episode>)>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError || snap.data == null) {
                  log('SponsorStore: load failed — ${snap.error}');
                  return _Message(
                    text: l.sponsorStoreLoadFailed,
                    onRetry: () =>
                        setState(() => _future = _load(_campaign)),
                  );
                }
                final (detail, episodes) = snap.data!;
                if (episodes.isEmpty) {
                  return _Message(text: l.sponsorStoreEmpty);
                }
                final visible = [
                  for (final e in episodes)
                    if (e.topics.intersection(_avoid).isEmpty) e,
                ];
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        Text(
                          l.sponsorStoreTitle(detail.name),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.sponsorStoreIntro,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _AvoidFilter(
                          avoid: _avoid,
                          onToggle: (t) => setState(
                            () => _avoid.contains(t)
                                ? _avoid.remove(t)
                                : _avoid.add(t),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (visible.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(l.sponsorStoreAllFiltered),
                          ),
                        for (final e in visible)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _EpisodeCard(
                              episode: e,
                              onOpen: () => drillDown(
                                context,
                                '/v/${e.video.id}/sponzoriraj',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String sponsorTopicLabel(SponsorTopic t, AppLocalizations l) => switch (t) {
  SponsorTopic.faith => l.sponsorTopicFaith,
  SponsorTopic.politics => l.sponsorTopicPolitics,
  SponsorTopic.business => l.sponsorTopicBusiness,
};

class _AvoidFilter extends StatelessWidget {
  final Set<SponsorTopic> avoid;
  final void Function(SponsorTopic topic) onToggle;

  const _AvoidFilter({required this.avoid, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.sponsorStoreAvoidTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final t in SponsorTopic.values)
              FilterChip(
                label: Text(sponsorTopicLabel(t, l)),
                selected: avoid.contains(t),
                onSelected: (_) => onToggle(t),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l.sponsorStoreAvoidHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final _Episode episode;
  final VoidCallback onOpen;

  const _EpisodeCard({required this.episode, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final v = episode.video;
    final free = [
      for (final o in episode.offers)
        if (o.state.isBuyable) o,
    ];
    final minPrice = free.isEmpty
        ? null
        : free.map((o) => o.priceCents).reduce((a, b) => a < b ? a : b);
    final muted = theme.colorScheme.onSurfaceVariant;

    final meta = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          v.displayTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final t in episode.topics)
              _Tag(text: sponsorTopicLabel(t, l), strong: true),
            for (final t in v.topics.take(3)) _Tag(text: t),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          [
            l.sponsorStoreFreeCount(free.length),
            if (minPrice != null) l.sponsorStoreFromPrice(fmtEur(minPrice)),
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final thumb = ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CachedThumbnail(
                        url: CdnConfig.thumbnailUrl(v.id),
                        width: c.maxWidth < 520 ? c.maxWidth : 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                  if (c.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [thumb, const SizedBox(height: 10), meta],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 200, child: thumb),
                      const SizedBox(width: 14),
                      Expanded(child: meta),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              SponsorTimelineBar(
                offers: episode.offers,
                durationSeconds: v.durationSeconds,
                height: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final bool strong;

  const _Tag({required this.text, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: strong
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
          color: strong
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _Message({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onRetry,
                child: Text(l.commonRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
