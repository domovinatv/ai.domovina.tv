import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart' show log;
import '../../models/channel_index.dart';
import '../../screens/home/home_feed.dart';
import '../../services/channel_cache.dart';
import '../../services/watch_progress_service.dart';
import 'widgets/tv_channel_card.dart';
import 'widgets/tv_episode_card.dart';
import 'widgets/tv_focus.dart';
import 'widgets/tv_hero.dart';
import 'widgets/tv_rail.dart';

/// Faza 2 TV home screen.
///
/// Layout (vertikalan scroll, jer EON SDSTB02 daje 540 dp visine pa hero +
/// 3 rail-a ne stane bez scrolla):
///
///   AppBar (kompaktan: wordmark + Pretraga gumb)
///   Hero (45% min(540, height), HomeFeed.pickFeatured) — autofocus PLAY
///   Rail: "Nastavi slušati" (samo ako WatchProgress ima itema)
///   Rail: "Najnovije epizode" (HomeFeed.latestEpisodes, 12 itema)
///   Rail: "Kanali" (sortirano po videoCount desc)
///
/// Sve interakcije su navigation:
/// - Hero PLAY → `/v/<id>`
/// - Episode card → `/v/<id>`
/// - Channel card → `/c/<slug>`
///
/// Pretraga je placeholder za Fazu 2.5 (vidi docs/android-tv.md).
class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  final _channelCache = channelCache;

  late final Future<ChannelIndex> _indexFuture = _channelCache.loadIndex();

  // "Nastavi slušati" rail — uživo iz WatchProgressService.
  List<WatchProgress> _continueWatching = [];

  // FocusNode-ovi za stabilan focus restore (npr. kad se vratimo sa episode
  // screena). U Faza 2 ne implementiramo restore — to je Faza 5 polish — ali
  // node-ove drzimo da fokus nije lost between rebuilds.
  final _searchFocus = FocusNode(debugLabel: 'tv-appbar-search');
  final _heroPlayFocus = FocusNode(debugLabel: 'tv-hero-play');

  @override
  void initState() {
    super.initState();
    log('TvHomeScreen.init (Faza 2 — real data wiring)');
    _channelCache.addListener(_onCacheUpdate);
    WatchProgressService.instance.addListener(_loadContinueWatching);
    _loadContinueWatching();
  }

  @override
  void dispose() {
    _channelCache.removeListener(_onCacheUpdate);
    WatchProgressService.instance.removeListener(_loadContinueWatching);
    _searchFocus.dispose();
    _heroPlayFocus.dispose();
    super.dispose();
  }

  void _onCacheUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadContinueWatching() async {
    final list =
        await WatchProgressService.instance.continueWatching(limit: 12);
    if (mounted) setState(() => _continueWatching = list);
  }

  void _openEpisode(String videoId) {
    log('TvHome: navigate /v/$videoId');
    context.go('/v/$videoId');
  }

  void _openChannel(ChannelSummary channel) {
    final slug = channel.id.replaceAll('_', '-');
    log('TvHome: navigate /c/$slug');
    context.go('/c/$slug');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaSize = MediaQuery.of(context).size;
    // EON: density 320 → 960×540 dp. Mac/Chrome: varira. Hero 45% visine,
    // clamp da ostane razuman za male i velike ekrane.
    final heroHeight = (mediaSize.height * 0.45).clamp(220.0, 380.0);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: FutureBuilder<ChannelIndex>(
          future: _indexFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return _buildLoading(theme, heroHeight);
            }
            if (snap.hasError) {
              return _buildError(theme, snap.error);
            }
            // Index ucitan — kick off per-channel prefetch.
            final channels = snap.data!.channels;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _channelCache.prefetchAll(channels);
            });
            return _buildContent(theme, heroHeight, channels);
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // States
  // ---------------------------------------------------------------------------

  Widget _buildLoading(ThemeData theme, double heroHeight) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAppBar(theme),
          _buildHeroSkeleton(theme, heroHeight),
          const SizedBox(height: 24),
          _buildRailSkeleton(theme, 'Učitavam…'),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme, Object? err) {
    log('TvHomeScreen: index ERROR — $err');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Text(
          'Greška pri učitavanju kanala:\n$err',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    double heroHeight,
    List<ChannelSummary> channels,
  ) {
    final allVids = _channelCache.allVideos;
    final hasMinData = HomeFeed.hasMinimumData(_channelCache);
    final featured = hasMinData ? HomeFeed.pickFeatured(allVids) : null;
    final latest = featured != null
        ? HomeFeed.latestEpisodes(allVids,
            limit: 12, excludeFeatured: featured.video)
        : <FeedVideo>[];

    // Channels sortirani po videoCount desc — bogatiji kanali prvi u rail-u.
    final sortedChannels = List<ChannelSummary>.from(channels)
      ..sort((a, b) => b.videoCount.compareTo(a.videoCount));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAppBar(theme),
          if (featured != null)
            TvHero(
              featured: featured,
              height: heroHeight,
              playFocusNode: _heroPlayFocus,
              autofocusPlay: true,
              onPlay: () => _openEpisode(featured.video.video.id),
            )
          else
            _buildHeroSkeleton(theme, heroHeight),

          const SizedBox(height: 24),

          if (_continueWatching.isNotEmpty) ...[
            TvRail(
              eyebrow: 'Nastavi slušati',
              height: 240,
              cards: [
                for (final wp in _continueWatching)
                  TvEpisodeCard(
                    episodeId: wp.episodeId,
                    title: wp.episodeTitle ?? wp.episodeId,
                    progress: wp.durationSeconds > 0
                        ? wp.positionSeconds / wp.durationSeconds
                        : null,
                    width: 280,
                    onTap: () => _openEpisode(wp.episodeId),
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          if (latest.isNotEmpty)
            TvRail(
              eyebrow: 'Najnovije epizode',
              height: 240,
              cards: [
                for (final fv in latest)
                  TvEpisodeCard(
                    episodeId: fv.video.id,
                    title: fv.video.displayTitle,
                    subtitle: fv.channelName,
                    magisteriumScore: fv.video.magisteriumScore,
                    width: 280,
                    onTap: () => _openEpisode(fv.video.id),
                  ),
              ],
            )
          else if (!hasMinData)
            _buildRailSkeleton(theme, 'Najnovije epizode'),

          const SizedBox(height: 24),

          if (sortedChannels.isNotEmpty)
            TvRail(
              eyebrow: 'Kanali (${sortedChannels.length})',
              height: 260,
              cards: [
                for (final c in sortedChannels)
                  TvChannelCard(
                    channel: c,
                    size: 200,
                    onTap: () => _openChannel(c),
                  ),
              ],
            ),

          const SizedBox(height: 32),
          _buildCacheStatus(theme),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // App bar
  // ---------------------------------------------------------------------------

  Widget _buildAppBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 24, 48, 8),
      child: Row(
        children: [
          Text(
            'DOMOVINA.ai',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          TvFocusable(
            style: TvFocusStyle.subtleButton,
            focusNode: _searchFocus,
            borderRadius: BorderRadius.circular(12),
            onActivate: () => log('TvHome: pretraga (Faza 2.5)'),
            builder: (context, focused) => AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: focused
                    ? theme.colorScheme.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search,
                    size: 22,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Pretraga',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Skeletons (minimal — full editorial skeleton je u home_screen.dart;
  // za TV cilj je tek 'nije prazno' indikacija dok prefetch traje).
  // ---------------------------------------------------------------------------

  Widget _buildHeroSkeleton(ThemeData theme, double height) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 16, 48, 0),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: CircularProgressIndicator(
          color: theme.colorScheme.primary,
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildRailSkeleton(ThemeData theme, String eyebrow) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 3,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 12),
              Text(
                eyebrow.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: 20),
              itemBuilder: (context, i) => Container(
                width: 280,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCacheStatus(ThemeData theme) {
    if (_channelCache.done) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Učitavam ${_channelCache.loaded}/${_channelCache.total} kanala…',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
