import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart' show log;
import '../../models/channel_index.dart';
import '../../screens/home/home_feed.dart';
import '../../services/cdn_config.dart';
import '../../services/channel_cache.dart';
import '../../services/watch_progress_service.dart';
import 'widgets/tv_channel_card.dart';
import 'widgets/tv_episode_card.dart';
import 'widgets/tv_focus.dart';
import 'widgets/tv_hero.dart';
import 'widgets/tv_loading_tips.dart';
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

  // Drzimo loading screen (tips) sve dok cijela startup sekvenca ne zavrsi:
  //   1. channel index ucitan (FutureBuilder vec hendla)
  //   2. ChannelCache.done — svih 40 kanala prefetchano
  //   3. HomeFeed.pickFeatured vrati featured pick (algoritam)
  //   4. Thumbnail tog feature pick-a je preloadan (precacheImage)
  // Bez ovoga korisnik vidi tips → onda hero skeleton → onda featured popne
  // gore (dvostruki "flash"). S ovime: tips → instant featured.
  bool _bootReady = false;
  bool _preloadingFeatured = false;

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
    if (!mounted) return;
    setState(() {});
    _maybeBootstrapFeatured();
  }

  /// Pri svakom cache update-u provjeri jesmo li dosegli boot-ready state.
  /// Kada `_channelCache.done` AND `pickFeatured != null`, preload-aj thumb
  /// i tek tad postavi `_bootReady = true` — UI prebaci na pravi content.
  Future<void> _maybeBootstrapFeatured() async {
    if (_bootReady || _preloadingFeatured) return;
    if (!_channelCache.done) return;
    final all = _channelCache.allVideos;
    final pick = HomeFeed.pickFeatured(all);
    if (pick == null) return;
    _preloadingFeatured = true;
    final thumbUrl = CdnConfig.thumbnailUrl(pick.video.video.id);
    log('TvHome: featured ${pick.video.video.id} — preloading thumbnail');
    try {
      await precacheImage(NetworkImage(thumbUrl), context);
    } catch (e) {
      log('TvHome: featured thumbnail preload failed: $e');
      // Ne blokiramo bootstrap na ovome — radije nudi content sa fallback
      // ikonom nego da forever zaglavi na loading screenu.
    }
    if (!mounted) return;
    setState(() => _bootReady = true);
    log('TvHome: boot ready — switching to content');
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
        // Flutter web ne mapira arrow keys na DirectionalFocusIntent po
        // defaultu (native Android TV salje DPAD_* keyeve koji Flutter okvir
        // sam hendla, ali u Chrome buildu samo Tab radi). Eksplicitno
        // bindamo arrow keys ovdje da TV layout radi i u Chrome/Mac dev
        // okruzenju. WidgetsApp.defaultShortcuts ne pokriva ovo na webu.
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowUp):
                DirectionalFocusIntent(TraversalDirection.up),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                DirectionalFocusIntent(TraversalDirection.down),
            SingleActivator(LogicalKeyboardKey.arrowLeft):
                DirectionalFocusIntent(TraversalDirection.left),
            SingleActivator(LogicalKeyboardKey.arrowRight):
                DirectionalFocusIntent(TraversalDirection.right),
          },
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
                _maybeBootstrapFeatured();
              });
              // Tips karousel ostaje vidljiv sve dok featured nije picked
              // I thumbnail preloadan — vidi `_maybeBootstrapFeatured`.
              if (!_bootReady) return _buildLoading(theme, heroHeight);
              return _buildContent(theme, heroHeight, channels);
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // States
  // ---------------------------------------------------------------------------

  Widget _buildLoading(ThemeData theme, double heroHeight) {
    // Channel index prefetch + featured pick + thumbnail preload trazi 3-10s.
    // Full-screen Slack-style tips karousel s 10s progress loaderom — bez
    // appbar-a / skeleton-a iza, zelimo da fokus bude na sadrzaju cekanja.
    return const TvLoadingTips(
      tips: defaultTvTips,
      progressDuration: Duration(seconds: 10),
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
    // Cekamo full prefetch prije nego pick-amo featured — bez ovoga
    // HomeFeed.pickFeatured se rebuilda na svakom channel cache update-u
    // (30% threshold pa onda done), pa korisnik vidi flash izmedju kandidata
    // 1-2s nakon load-a. S done-gate-om hero ostaje skeleton dok ne stigne
    // stabilan izbor.
    final cacheReady = _channelCache.done;
    final featured = cacheReady ? HomeFeed.pickFeatured(allVids) : null;
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
              maxHeight: heroHeight,
              playFocusNode: _heroPlayFocus,
              autofocusPlay: true,
              onPlay: () => _openEpisode(featured.video.video.id),
            )
          else
            _buildHeroSkeleton(theme, heroHeight),

          // Veci gap izmedju hero-a i prvog rail-a — focused card scale 1.18
          // + glow shadow s `Clip.none` na rail-u overflowa vertikalno, pa
          // bez ovog prostora gornji rub kartice udara u hero ispod.
          const SizedBox(height: 40),

          if (_continueWatching.isNotEmpty) ...[
            TvRail(
              eyebrow: 'Nastavi slušati',
              height: 200,
              cards: [
                for (final wp in _continueWatching)
                  TvEpisodeCard(
                    episodeId: wp.episodeId,
                    title: wp.episodeTitle ?? wp.episodeId,
                    progress: wp.durationSeconds > 0
                        ? wp.positionSeconds / wp.durationSeconds
                        : null,
                    width: 160,
                    onTap: () => _openEpisode(wp.episodeId),
                  ),
              ],
            ),
            const SizedBox(height: 36),
          ],

          if (latest.isNotEmpty)
            TvRail(
              eyebrow: 'Najnovije epizode',
              height: 200,
              cards: [
                for (final fv in latest)
                  TvEpisodeCard(
                    episodeId: fv.video.id,
                    title: fv.video.displayTitle,
                    subtitle: fv.channelName,
                    magisteriumScore: fv.video.magisteriumScore,
                    width: 160,
                    onTap: () => _openEpisode(fv.video.id),
                  ),
              ],
            )
          else if (!cacheReady)
            _buildRailSkeleton(theme, 'Najnovije epizode'),

          const SizedBox(height: 36),

          if (sortedChannels.isNotEmpty)
            TvRail(
              eyebrow: 'Kanali (${sortedChannels.length})',
              height: 215,
              cards: [
                for (final c in sortedChannels)
                  TvChannelCard(
                    channel: c,
                    size: 130,
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

  /// Skeleton koji prati `TvHero` shape (max 1200dp wide, slika lijevo / blok
  /// desno) — bez ovoga bi layout poskocio kad real hero stigne.
  Widget _buildHeroSkeleton(ThemeData theme, double maxHeight) {
    final compact = maxHeight < 280;
    final imageWidth = (maxHeight * 16 / 9).clamp(360.0, 540.0);
    final block = theme.colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 16, 48, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: theme.colorScheme.surfaceContainerLowest,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: imageWidth,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          color: block,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              color: theme.colorScheme.primary,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 24 : 36,
                          compact ? 20 : 28,
                          compact ? 24 : 36,
                          compact ? 20 : 28,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _SkeletonBar(width: 140, height: 14, color: block),
                            SizedBox(height: compact ? 14 : 18),
                            _SkeletonBar(
                                width: double.infinity, height: 22, color: block),
                            const SizedBox(height: 10),
                            _SkeletonBar(width: 260, height: 22, color: block),
                            SizedBox(height: compact ? 14 : 18),
                            _SkeletonBar(width: 200, height: 14, color: block),
                            SizedBox(height: compact ? 18 : 26),
                            _SkeletonBar(width: 180, height: 44, color: block),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
          const SizedBox(height: 14),
          SizedBox(
            height: 182,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: 20),
              itemBuilder: (context, i) => Container(
                width: 160,
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

class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonBar({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
