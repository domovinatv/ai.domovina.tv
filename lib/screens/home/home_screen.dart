import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart' show log;
import '../../models/channel_index.dart';
import '../../services/cdn_config.dart';
import '../../services/channel_cache.dart';
import '../../services/local_prefs.dart';
import '../../services/view_mode.dart';
import '../../services/watch_progress_service.dart';
import 'channel_card.dart';
import 'episode_rail_card.dart';
import 'episodes_rail.dart';
import 'footer.dart';
import 'home_app_bar.dart';
import 'home_feed.dart';
import 'hero_section.dart';
import 'search_overlay.dart';
import 'skeletons.dart';
import 'sort_mode.dart';

const _channelOrderKey = 'channel_order';

// ---------------------------------------------------------------------------
// Channel order persistence
// ---------------------------------------------------------------------------
// Web: SharedPreferences throws MissingPluginException in release builds
//      (dart2js strips the method channel registration). Use localStorage.
// Native (iOS/Android/macOS): SharedPreferences works normally.
// ---------------------------------------------------------------------------

List<String>? _loadOrderWeb() {
  final raw = getLocalStorageString(_channelOrderKey);
  if (raw == null) return null;
  return raw.split(',');
}

void _saveOrderWeb(List<String> ids) {
  setLocalStorageString(_channelOrderKey, ids.join(','));
}

/// Privremeni placeholder za feature-e koji jos nisu spojeni (npr. "Spremi"
/// gumb na hero kartici). Cijela favoriti integracija stize u sljedecem koraku.
void _showComingSoon(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Funkcija stiže uskoro'),
      duration: Duration(seconds: 2),
    ),
  );
}

/// Home screen — channel grid + search + manual YouTube ID input.
///
/// Razdvojeno iz monolitnog `lib/screens/home_screen.dart` u Korak 2 redizajna.
/// Channel detail view (`/c/:slug`) sad ima vlastiti `ChannelScreen` widget
/// (vidi `lib/screens/channel/channel_screen.dart`).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _channelCache = channelCache;

  late Future<ChannelIndex> _indexFuture;

  // Ordered channel list (shuffled once, persisted)
  List<ChannelSummary>? _orderedChannels;

  // Simple/Detailed mode — auto-defaults to simple on mobile
  bool _simpleMode = false;
  bool _simpleModeLoaded = false;

  // "Nastavi slušati" rail data — live from WatchProgressService.
  List<WatchProgress> _continueWatching = [];

  // Sort mode za channel grid.
  ChannelSortMode _sortMode = ChannelSortMode.custom;

  @override
  void initState() {
    super.initState();
    _indexFuture = _channelCache.loadIndex();
    _channelCache.addListener(_onCacheUpdate);
    WatchProgressService.instance.addListener(_loadContinueWatching);
    _loadSimpleMode();
    _loadContinueWatching();
    _initSortMode();
  }

  Future<void> _initSortMode() async {
    final saved = await loadSortMode();
    if (saved != null) {
      if (mounted) setState(() => _sortMode = saved);
      return;
    }
    // Migracija s legacy channel_order — ako postoji, znaci da je user
    // ranije imao shuffle redoslijed; nemoj mu ga resetirati.
    List<String>? legacy;
    if (kIsWeb) {
      legacy = _loadOrderWeb();
    } else {
      final prefs = await SharedPreferences.getInstance();
      legacy = prefs.getStringList(_channelOrderKey);
    }
    final initial = (legacy != null && legacy.isNotEmpty)
        ? ChannelSortMode.custom
        : ChannelSortMode.newest;
    await saveSortMode(initial);
    if (mounted) setState(() => _sortMode = initial);
  }

  Future<void> _setSortMode(ChannelSortMode mode) async {
    await saveSortMode(mode);
    final index = await _indexFuture;
    List<String>? customOrder;
    if (mode == ChannelSortMode.custom) {
      if (kIsWeb) {
        customOrder = _loadOrderWeb();
      } else {
        final prefs = await SharedPreferences.getInstance();
        customOrder = prefs.getStringList(_channelOrderKey);
      }
    }
    if (!mounted) return;
    setState(() {
      _sortMode = mode;
      _orderedChannels =
          applySortMode(index.channels, mode, customOrder: customOrder);
    });
  }

  Future<void> _loadContinueWatching() async {
    final list =
        await WatchProgressService.instance.continueWatching(limit: 12);
    if (mounted) setState(() => _continueWatching = list);
  }

  Future<void> _loadSimpleMode() async {
    final saved = await loadSimpleModePref();
    if (mounted) {
      setState(() {
        _simpleMode = saved ?? false;
        _simpleModeLoaded = true;
      });
    }
  }

  void _onCacheUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _channelCache.removeListener(_onCacheUpdate);
    WatchProgressService.instance.removeListener(_loadContinueWatching);
    super.dispose();
  }

  /// Otvara search overlay modal — koristi se i za app bar search trigger
  /// i za Cmd+K shortcut.
  Future<void> _openSearchOverlay() async {
    final index = _channelCache.index;
    if (index == null) return; // index jos nije ucitan
    await showSearchOverlay(
      context,
      channels: index.channels,
      onSelectChannel: _selectChannel,
      onSelectVideo: _openVideo,
      onSelectVideoAt: _openVideoAt,
    );
  }

  /// Otvori epizodu na zadanom timestampu (semantic search deep link).
  void _openVideoAt(String videoId, int seconds) {
    context.go('/v/$videoId/t/$seconds');
  }

  /// Primijeni aktivni sort mode na kanale. Za 'custom' mode koristi spremljen
  /// channel_order; ako ga nema, prvi put generira shuffle i sprema.
  Future<List<ChannelSummary>> _applyOrder(
      List<ChannelSummary> channels) async {
    List<String>? savedOrder;
    if (kIsWeb) {
      savedOrder = _loadOrderWeb();
    } else {
      final prefs = await SharedPreferences.getInstance();
      savedOrder = prefs.getStringList(_channelOrderKey);
    }

    if (_sortMode == ChannelSortMode.custom) {
      if (savedOrder != null && savedOrder.isNotEmpty) {
        return applySortMode(channels, ChannelSortMode.custom,
            customOrder: savedOrder);
      }
      // First visit s custom mode — shuffle and persist.
      final shuffled = List<ChannelSummary>.from(channels)..shuffle(Random());
      final ids = shuffled.map((c) => c.id).toList();
      if (kIsWeb) {
        _saveOrderWeb(ids);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_channelOrderKey, ids);
      }
      return shuffled;
    }

    return applySortMode(channels, _sortMode, customOrder: savedOrder);
  }

  Future<void> _shuffle() async {
    if (_orderedChannels == null) return;
    final shuffled = List<ChannelSummary>.from(_orderedChannels!)
      ..shuffle(Random());
    final ids = shuffled.map((c) => c.id).toList();

    if (kIsWeb) {
      _saveOrderWeb(ids);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_channelOrderKey, ids);
    }
    // Shuffle implicitno postavlja mode na custom — to su user-owned redoslijed.
    await saveSortMode(ChannelSortMode.custom);
    if (!mounted) return;
    setState(() {
      _sortMode = ChannelSortMode.custom;
      _orderedChannels = shuffled;
    });
  }

  void _selectChannel(ChannelSummary channel) {
    final slug = channel.id.replaceAll('_', '-');
    context.go('/c/$slug');
  }

  void _openVideo(String videoId) {
    if (_simpleMode) {
      context.go('/m/$videoId');
    } else {
      context.go('/v/$videoId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            // Cmd+K (macOS) / Ctrl+K (Windows/Linux) → otvara search overlay.
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                _openSearchOverlay,
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                _openSearchOverlay,
          },
          child: Focus(
            autofocus: true,
            child: _ChannelGridView(
              indexFuture: _indexFuture,
              orderedChannels: _orderedChannels,
              channelCache: _channelCache,
              continueWatching: _continueWatching,
              sortMode: _sortMode,
              onSortModeChanged: _setSortMode,
              onChannelsLoaded: (channels) async {
                final ordered = await _applyOrder(channels);
                if (mounted) {
                  setState(() => _orderedChannels = ordered);
                  if (!_simpleModeLoaded) return;
                }
                _channelCache.prefetchAll(channels);
              },
              onChannelTap: _selectChannel,
              onShuffle: _shuffle,
              onSearchTap: _openSearchOverlay,
              onVideoTap: _openVideo,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Channel grid
// ---------------------------------------------------------------------------

class _ChannelGridView extends StatelessWidget {
  final Future<ChannelIndex> indexFuture;
  final List<ChannelSummary>? orderedChannels;
  final ChannelCache channelCache;
  final List<WatchProgress> continueWatching;
  final ChannelSortMode sortMode;
  final Future<void> Function(ChannelSortMode) onSortModeChanged;
  final Future<void> Function(List<ChannelSummary>) onChannelsLoaded;
  final void Function(ChannelSummary) onChannelTap;
  final VoidCallback onShuffle;
  final VoidCallback onSearchTap;
  final void Function(String videoId) onVideoTap;

  const _ChannelGridView({
    required this.indexFuture,
    required this.orderedChannels,
    required this.channelCache,
    required this.continueWatching,
    required this.sortMode,
    required this.onSortModeChanged,
    required this.onChannelsLoaded,
    required this.onChannelTap,
    required this.onShuffle,
    required this.onSearchTap,
    required this.onVideoTap,
  });

  static const double _maxCardWidth = 360;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<ChannelIndex>(
      future: indexFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return CustomScrollView(
            slivers: [
              HomeAppBar(onSearchTap: onSearchTap),
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }
        if (snap.hasError) {
          log('ChannelIndex ERROR: ${snap.error}');
          return CustomScrollView(
            slivers: [
              HomeAppBar(onSearchTap: onSearchTap),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        'Greška pri učitavanju kanala:\n${snap.error}',
                        textAlign: TextAlign.center),
                  ),
                ),
              ),
            ],
          );
        }

        // Trigger order computation once
        final raw = snap.data!.channels;
        if (orderedChannels == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => onChannelsLoaded(raw));
          return LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              return CustomScrollView(
                slivers: [
                  HomeAppBar(onSearchTap: onSearchTap),
                  SliverToBoxAdapter(
                      child: HeroSkeleton(isMobile: isMobile)),
                  SliverToBoxAdapter(
                      child: RailSkeleton(isMobile: isMobile)),
                  SliverToBoxAdapter(
                      child: ChannelGridSkeleton(isMobile: isMobile)),
                ],
              );
            },
          );
        }

        final channels = orderedChannels!;

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isMobile = width < 600;

            // Search rezultati su sada u overlay-u (Cmd+K). Channel grid
            // uvijek pokazuje pun listing po aktivnom sort modu.
            final allVids = channelCache.allVideos;
            final hasMinData = HomeFeed.hasMinimumData(channelCache);
            final featured =
                hasMinData ? HomeFeed.pickFeatured(allVids) : null;
            // "Upravo stiglo" — tek pristigle, još neobrađene epizode.
            final freshlyArrived = featured != null
                ? HomeFeed.freshlyArrived(allVids,
                    limit: 12, excludeFeatured: featured.video)
                : const <FeedVideo>[];

            return CustomScrollView(
              slivers: [
                HomeAppBar(onSearchTap: onSearchTap),
                SliverToBoxAdapter(
                  child: _HomeHeader(
                    cacheProgress: channelCache.done
                        ? null
                        : (channelCache.loaded, channelCache.total),
                    isMobile: isMobile,
                  ),
                ),

                // Hero — featured epizoda (ili skeleton dok prefetch ne stigne).
                if (featured != null)
                  SliverToBoxAdapter(
                    child: HeroSection(
                      featured: featured,
                      isMobile: isMobile,
                      onPlay: () => onVideoTap(featured.video.video.id),
                      onSave: () => _showComingSoon(context),
                    ),
                  )
                else if (!hasMinData)
                  SliverToBoxAdapter(
                    child: HeroSkeleton(isMobile: isMobile),
                  ),

                // "Nastavi slušati" rail — samo ako ima itema.
                // Thumbnail uvijek konstruiramo iz CDN-a (ignoriraj denorm
                // episodeThumbnailUrl ako pokazuje na i.ytimg.com — stari
                // zapisi prije fix-a). Sad smo deterministicki.
                if (continueWatching.isNotEmpty)
                  SliverToBoxAdapter(
                    child: EpisodesRail(
                      eyebrow: 'Nastavi slušati',
                      isMobile: isMobile,
                      cards: continueWatching
                          .map((wp) => EpisodeRailCard(
                                title: wp.episodeTitle ?? wp.episodeId,
                                thumbnailUrl:
                                    CdnConfig.thumbnailUrl(wp.episodeId),
                                progress: wp.durationSeconds > 0
                                    ? wp.positionSeconds / wp.durationSeconds
                                    : null,
                                width: isMobile ? 180 : 220,
                                onTap: () => onVideoTap(wp.episodeId),
                              ))
                          .toList(),
                    ),
                  ),

                // "Najnovije epizode" rail — cross-channel po datumu desc.
                // CDN URL eksplicitno (`fv.video.thumbnail` moze biti ytimg
                // URL iz pipeline-a, sto blokira CORS na web build-u).
                if (featured != null && allVids.isNotEmpty)
                  SliverToBoxAdapter(
                    child: EpisodesRail(
                      eyebrow: 'Najnovije epizode',
                      isMobile: isMobile,
                      cards: HomeFeed.latestEpisodes(allVids,
                              limit: 12, excludeFeatured: featured.video)
                          .map((fv) => EpisodeRailCard(
                                title: fv.video.displayTitle,
                                subtitle: fv.channelName,
                                thumbnailUrl:
                                    CdnConfig.thumbnailUrl(fv.video.id),
                                dateLabel: fv.video.date,
                                magisteriumScore: fv.video.magisteriumScore,
                                width: isMobile ? 180 : 220,
                                onTap: () => onVideoTap(fv.video.id),
                              ))
                          .toList(),
                    ),
                  )
                else if (!hasMinData)
                  SliverToBoxAdapter(child: RailSkeleton(isMobile: isMobile)),

                // "Upravo stiglo" rail — tek pristigle epizode bez članka
                // (has_article:false). Kronološki su među najnovijima, ali ih
                // "Najnovije" sakriva jer nemaju AI obradu. Surfamo ih gledljive
                // uz "U obradi" oznaku; tap vodi na basic episode layout
                // (video + YouTube, bez članka).
                if (freshlyArrived.isNotEmpty)
                  SliverToBoxAdapter(
                    child: EpisodesRail(
                      eyebrow: 'Upravo stiglo',
                      isMobile: isMobile,
                      cards: freshlyArrived
                          .map((fv) => EpisodeRailCard(
                                title: fv.video.displayTitle,
                                subtitle: fv.channelName,
                                thumbnailUrl:
                                    CdnConfig.thumbnailUrl(fv.video.id),
                                dateLabel: fv.video.date,
                                statusBadge: 'U obradi',
                                width: isMobile ? 180 : 220,
                                onTap: () => onVideoTap(fv.video.id),
                              ))
                          .toList(),
                    ),
                  ),

                if (channels.isNotEmpty) ...[
                  // Sekcija naslov "KANALI (23)" + sort dropdown desno
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 2,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'KANALI (${channels.length})',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const Spacer(),
                          _SortDropdown(
                            mode: sortMode,
                            onChanged: onSortModeChanged,
                            onShuffle: onShuffle,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: _buildWrap(channels, width),
                    ),
                  ),
                ],

                SliverToBoxAdapter(child: HomeFooter(channels: channels)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWrap(List<ChannelSummary> channels, double screenWidth) {
    final availableWidth = screenWidth - 32;
    // Mobile (< 600): 1 stupac. Tablet/desktop: clamp na minimum 320px width.
    final columns = screenWidth < 600
        ? 1
        : (availableWidth / _maxCardWidth).floor().clamp(2, 99);
    final cardWidth = columns == 1
        ? availableWidth
        : (availableWidth - (columns - 1) * 16) / columns;

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (int i = 0; i < channels.length; i++)
          SizedBox(
            width: cardWidth,
            child: ChannelCard(
              channel: channels[i],
              onTap: () => onChannelTap(channels[i]),
            ),
          ),
      ],
    );
  }

}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// Minimalan sub-bar ispod app bara — prikazuje samo progres ucitavanja
/// kanala. Kad je cache gotov, kolabira na nista (bez praznog paddinga).
///
/// View-mode prebacivanje (Detaljno/Jednostavno) je maknuto odavde — sada
/// zivi samo na episode ekranima (vidi episode_screen.dart / episode_simple_screen.dart),
/// gdje je jasno labelirano. Search i YouTube ID input su u Cmd+K overlay-u.
class _HomeHeader extends StatelessWidget {
  final (int, int)? cacheProgress; // (loaded, total) — null kad je gotovo
  final bool isMobile;

  const _HomeHeader({
    this.cacheProgress,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (cacheProgress == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, isMobile ? 4 : 8),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Učitavam ${cacheProgress!.$1}/${cacheProgress!.$2} kanala…',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search result card for a video found across all channels.
// ---------------------------------------------------------------------------

/// PopupMenuButton-based sort selektor pored "KANALI (X)" sekcijskog naslova.
///
/// Sadrži sve sort opcije + shuffle kao posebnu akciju (shuffle re-randomizira
/// i prebacuje mode na `custom`).
class _SortDropdown extends StatelessWidget {
  final ChannelSortMode mode;
  final Future<void> Function(ChannelSortMode) onChanged;
  final VoidCallback onShuffle;

  const _SortDropdown({
    required this.mode,
    required this.onChanged,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Sortiraj kanale',
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (value) {
        if (value == '__shuffle__') {
          onShuffle();
        } else {
          final m = ChannelSortMode.values.firstWhere((e) => e.name == value);
          onChanged(m);
        }
      },
      itemBuilder: (context) => [
        for (final m in ChannelSortMode.values)
          PopupMenuItem<String>(
            value: m.name,
            child: Row(
              children: [
                Icon(
                  m == mode ? Icons.check : Icons.circle_outlined,
                  size: 14,
                  color: m == mode
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.3),
                ),
                const SizedBox(width: 10),
                Text(m.label, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__shuffle__',
          child: Row(
            children: [
              Icon(Icons.shuffle,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text('Promiješaj', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mode.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
