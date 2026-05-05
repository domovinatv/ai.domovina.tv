import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:fuzzy/fuzzy.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show appVersion, log;
import '../models/channel_index.dart';
import '../models/channel_detail.dart';
import '../services/channel_cache.dart';
import '../services/local_prefs.dart';
import '../services/update_notifier.dart';
import '../widgets/magisterium_section.dart';

/// Croatian flag colours extracted from the logo SVG.
const _croRed = Color(0xFFFF0000);
const _croBlue = Color(0xFF002F6C);

const _channelOrderKey = 'channel_order';
const _simpleModeKey = 'simple_mode';

/// Module-level cache za search query — prezivljava rebuild HomeScreena
/// kad user ode na /v/ episode i vrati se. Resetira se tek na restart app-a.
String _cachedSearchQuery = '';

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

// ---------------------------------------------------------------------------
// Simple mode persistence
// ---------------------------------------------------------------------------

bool? _loadSimpleModeWeb() {
  final raw = getLocalStorageString(_simpleModeKey);
  if (raw == null) return null;
  return raw == 'true';
}

void _saveSimpleModeWeb(bool value) {
  setLocalStorageString(_simpleModeKey, value.toString());
}

class HomeScreen extends StatefulWidget {
  final String? initialChannelId;

  const HomeScreen({super.key, this.initialChannelId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _idController = TextEditingController();
  final _searchController =
      TextEditingController(text: _cachedSearchQuery);
  final _formKey = GlobalKey<FormState>();
  final _channelCache = channelCache;
  Timer? _debounce;
  String _searchQuery = _cachedSearchQuery;

  late Future<ChannelIndex> _indexFuture;
  String? _selectedChannelId;
  String? _selectedChannelName;
  Future<ChannelDetail>? _channelFuture;

  // Ordered channel list (shuffled once, persisted)
  List<ChannelSummary>? _orderedChannels;

  // Simple/Detailed mode — auto-defaults to simple on mobile
  bool _simpleMode = false;
  bool _simpleModeLoaded = false;

  @override
  void initState() {
    super.initState();
    _indexFuture = _channelCache.loadIndex();
    _channelCache.addListener(_onCacheUpdate);
    if (widget.initialChannelId != null) {
      _selectedChannelId = widget.initialChannelId;
      _channelFuture = _channelCache.loadChannel(widget.initialChannelId!);
    }
    _loadSimpleMode();
  }

  Future<void> _loadSimpleMode() async {
    bool? saved;
    if (kIsWeb) {
      saved = _loadSimpleModeWeb();
    } else {
      final prefs = await SharedPreferences.getInstance();
      saved = prefs.getBool(_simpleModeKey);
    }
    if (mounted) {
      setState(() {
        // If user has never set preference, auto-detect mobile
        _simpleMode = saved ?? false;
        _simpleModeLoaded = true;
      });
    }
  }

  Future<void> _toggleSimpleMode(bool value) async {
    setState(() => _simpleMode = value);
    if (kIsWeb) {
      _saveSimpleModeWeb(value);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_simpleModeKey, value);
    }
  }

  void _onCacheUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _idController.dispose();
    _searchController.dispose();
    _channelCache.removeListener(_onCacheUpdate);
    super.dispose();
  }

  /// Apply saved order or shuffle for first-time visitors, then persist.
  /// Web: localStorage (SharedPreferences crashes in release).
  /// Native: SharedPreferences.
  Future<List<ChannelSummary>> _applyOrder(
      List<ChannelSummary> channels) async {
    List<String>? savedOrder;

    if (kIsWeb) {
      savedOrder = _loadOrderWeb();
    } else {
      final prefs = await SharedPreferences.getInstance();
      savedOrder = prefs.getStringList(_channelOrderKey);
    }

    if (savedOrder != null && savedOrder.isNotEmpty) {
      final byId = {for (final ch in channels) ch.id: ch};
      final ordered = <ChannelSummary>[];
      for (final id in savedOrder) {
        final ch = byId.remove(id);
        if (ch != null) ordered.add(ch);
      }
      ordered.addAll(byId.values);
      return ordered;
    }

    // First visit — shuffle and save
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
    setState(() => _orderedChannels = shuffled);
  }

  void _selectChannel(ChannelSummary channel) {
    final slug = channel.id.replaceAll('_', '-');
    context.go('/c/$slug');
  }

  void _back() {
    context.go('/');
  }

  void _openVideo(String videoId) {
    if (_simpleMode) {
      context.go('/m/$videoId');
    } else {
      context.go('/v/$videoId');
    }
  }

  void _openManual() {
    if (!_formKey.currentState!.validate()) return;
    _openVideo(_idController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isChannel = _selectedChannelId != null;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: isChannel
            ? _VideoGridView(
                channelFuture: _channelFuture!,
                channelName: _selectedChannelName,
                channelId: _selectedChannelId!,
                onResolvedName: (name) {
                  if (_selectedChannelName == null && mounted) {
                    setState(() => _selectedChannelName = name);
                  }
                },
                onBack: _back,
                onVideoTap: _openVideo,
              )
            : _ChannelGridView(
              indexFuture: _indexFuture,
              orderedChannels: _orderedChannels,
              searchQuery: _searchQuery,
              channelCache: _channelCache,
              onChannelsLoaded: (channels) async {
                final ordered = await _applyOrder(channels);
                if (mounted) {
                  setState(() => _orderedChannels = ordered);
                  // Auto-detect mobile on first load if no saved preference
                  if (!_simpleModeLoaded) return;
                }
                // Prefetch svih channel detaila u pozadini
                _channelCache.prefetchAll(channels);
              },
              onChannelTap: _selectChannel,
              onShuffle: _shuffle,
              searchController: _searchController,
              onSearchChanged: (q) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 400),
                  () => setState(() {
                    _searchQuery = q;
                    _cachedSearchQuery = q;
                  }),
                );
              },
              idController: _idController,
              formKey: _formKey,
              onManualOpen: _openManual,
              simpleMode: _simpleMode,
              onSimpleModeChanged: _toggleSimpleMode,
              onVideoTap: _openVideo,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Channel grid
// ---------------------------------------------------------------------------

class _ChannelGridView extends StatelessWidget {
  final Future<ChannelIndex> indexFuture;
  final List<ChannelSummary>? orderedChannels;
  final String searchQuery;
  final ChannelCache channelCache;
  final Future<void> Function(List<ChannelSummary>) onChannelsLoaded;
  final void Function(ChannelSummary) onChannelTap;
  final VoidCallback onShuffle;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final TextEditingController idController;
  final GlobalKey<FormState> formKey;
  final VoidCallback onManualOpen;
  final bool simpleMode;
  final ValueChanged<bool> onSimpleModeChanged;
  final void Function(String videoId) onVideoTap;

  const _ChannelGridView({
    required this.indexFuture,
    required this.orderedChannels,
    required this.searchQuery,
    required this.channelCache,
    required this.onChannelsLoaded,
    required this.onChannelTap,
    required this.onShuffle,
    required this.searchController,
    required this.onSearchChanged,
    required this.idController,
    required this.formKey,
    required this.onManualOpen,
    required this.simpleMode,
    required this.onSimpleModeChanged,
    required this.onVideoTap,
  });

  static const double _maxCardWidth = 530;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<ChannelIndex>(
      future: indexFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          log('ChannelIndex ERROR: ${snap.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Greska pri ucitavanju kanala:\n${snap.error}',
                  textAlign: TextAlign.center),
            ),
          );
        }

        // Trigger order computation once
        final raw = snap.data!.channels;
        if (orderedChannels == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => onChannelsLoaded(raw));
          return const Center(child: CircularProgressIndicator());
        }

        final allChannels = orderedChannels!;

        // Fuzzy search — kanali + video zapisi (kad je cache spreman)
        final List<ChannelSummary> channels;
        final List<({String channelId, String channelName, ChannelVideo video})>
            videoResults;

        if (searchQuery.isEmpty) {
          channels = allChannels;
          videoResults = [];
        } else {
          // Fuzzy search po kanalima
          final channelFuse = Fuzzy<ChannelSummary>(
            allChannels,
            options: FuzzyOptions(
              keys: [
                WeightedKey(
                    name: 'name', getter: (c) => c.name, weight: 1),
              ],
              threshold: 0.4,
            ),
          );
          channels =
              channelFuse.search(searchQuery).map((r) => r.item).toList();

          // Fuzzy search po svim video zapisima (ako je cache spreman)
          final allVids = channelCache.allVideos;
          if (allVids.isNotEmpty) {
            final videoFuse = Fuzzy<
                ({
                  String channelId,
                  String channelName,
                  ChannelVideo video
                })>(
              allVids,
              options: FuzzyOptions(
                keys: [
                  WeightedKey(
                    name: 'title',
                    getter: (v) => v.video.displayTitle,
                    weight: 1,
                  ),
                  WeightedKey(
                    name: 'speakers',
                    getter: (v) => v.video.speakers.join(' '),
                    weight: 0.5,
                  ),
                ],
                threshold: 0.4,
              ),
            );
            videoResults = videoFuse
                .search(searchQuery)
                .take(20)
                .map((r) => r.item)
                .toList();
          } else {
            videoResults = [];
          }
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isMobile = width < 600;
            final hasResults = channels.isNotEmpty || videoResults.isNotEmpty;

            return CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: _HomeHeader(
                    channelCount: allChannels.length,
                    cacheProgress: channelCache.done
                        ? null
                        : (channelCache.loaded, channelCache.total),
                    onShuffle: onShuffle,
                    searchController: searchController,
                    onSearchChanged: onSearchChanged,
                    idController: idController,
                    formKey: formKey,
                    onManualOpen: onManualOpen,
                    isMobile: isMobile,
                    simpleMode: simpleMode,
                    onSimpleModeChanged: onSimpleModeChanged,
                  ),
                ),

                // No results
                if (!hasResults && searchQuery.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'Nema rezultata za "$searchQuery"',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ),

                // Channel results
                if (channels.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: isMobile
                        ? SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) => _ChannelListCard(
                                channel: channels[i],
                                onTap: () => onChannelTap(channels[i]),
                              ),
                              childCount: channels.length,
                            ),
                          )
                        : SliverToBoxAdapter(
                            child: _buildWrap(channels, width),
                          ),
                  ),

                // Video search results
                if (videoResults.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Text(
                        'Video zapisi (${videoResults.length})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final vr = videoResults[i];
                          return _VideoSearchCard(
                            video: vr.video,
                            channelName: vr.channelName,
                            onTap: () => onVideoTap(vr.video.id),
                          );
                        },
                        childCount: videoResults.length,
                      ),
                    ),
                  ),
                ],

                // Footer: version
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: GestureDetector(
                        onTap: kIsWeb ? hardReload : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'v$appVersion',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withAlpha(100),
                                fontFamily: 'monospace',
                              ),
                            ),
                            if (kIsWeb) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.refresh,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withAlpha(100),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWrap(List<ChannelSummary> channels, double screenWidth) {
    final availableWidth = screenWidth - 32;
    final columns = (availableWidth / _maxCardWidth).floor().clamp(2, 99);
    final cardWidth = (availableWidth - (columns - 1) * 12) / columns;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (int i = 0; i < channels.length; i++)
          SizedBox(
            width: cardWidth,
            child: _ChannelGridCard(
              channel: channels[i],
              index: i,
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

class _HomeHeader extends StatelessWidget {
  final int channelCount;
  final (int, int)? cacheProgress; // (loaded, total) — null kad je gotovo
  final VoidCallback onShuffle;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final TextEditingController idController;
  final GlobalKey<FormState> formKey;
  final VoidCallback onManualOpen;
  final bool isMobile;
  final bool simpleMode;
  final ValueChanged<bool> onSimpleModeChanged;

  const _HomeHeader({
    required this.channelCount,
    this.cacheProgress,
    required this.onShuffle,
    required this.searchController,
    required this.onSearchChanged,
    required this.idController,
    required this.formKey,
    required this.onManualOpen,
    required this.isMobile,
    required this.simpleMode,
    required this.onSimpleModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerLowest,
        border: Border.all(
          color: _croBlue.withAlpha(isDark ? 50 : 30),
        ),
      ),
      child: Column(
        children: [
          // Croatian tricolour accent bar
          Row(
            children: [
              Expanded(child: Container(height: 4, color: _croRed)),
              Expanded(child: Container(height: 4, color: Colors.white)),
              Expanded(child: Container(height: 4, color: _croBlue)),
            ],
          ),
          Padding(
            padding: EdgeInsets.all(isMobile ? 20 : 28),
            child: isMobile ? _buildMobile(theme, isDark) : _buildDesktop(theme, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop(ThemeData theme, bool isDark) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left: logo icon + branding
            Expanded(
              child: Row(
                children: [
                  Image.asset(
                    'assets/icons/domovina_ai_logo_1024.png',
                    width: 52,
                    height: 52,
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _logoText(theme, isDark),
                      const SizedBox(height: 4),
                      _subtitle(theme),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Right: YouTube ID input + shuffle
            SizedBox(
              width: 340,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _idInput(theme, isDark),
                  const SizedBox(height: 8),
                  _shuffleRow(theme),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _searchInput(theme),
      ],
    );
  }

  Widget _buildMobile(ThemeData theme, bool isDark) {
    return Column(
      children: [
        Image.asset(
          'assets/icons/domovina_ai_logo_1024.png',
          width: 56,
          height: 56,
        ),
        const SizedBox(height: 12),
        _logoText(theme, isDark),
        const SizedBox(height: 4),
        _subtitle(theme),
        const SizedBox(height: 12),
        _searchInput(theme),
        const SizedBox(height: 12),
        _idInput(theme, isDark),
        const SizedBox(height: 8),
        _shuffleRow(theme),
      ],
    );
  }

  Widget _logoText(ThemeData theme, bool isDark) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'DOMOVINA',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : _croBlue,
              letterSpacing: 1.5,
            ),
          ),
          TextSpan(
            text: '.ai',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _croRed,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
      textAlign: isMobile ? TextAlign.center : TextAlign.start,
    );
  }

  Widget _subtitle(ThemeData theme) {
    return Text(
      '$channelCount kanala  •  AI-obradeni hrvatski podcasti',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.3,
      ),
      textAlign: isMobile ? TextAlign.center : TextAlign.start,
    );
  }

  Widget _searchInput(ThemeData theme) {
    final hint = cacheProgress != null
        ? 'Ucitavam ${cacheProgress!.$1}/${cacheProgress!.$2} kanala...'
        : 'Pretrazi kanale i video zapise...';
    return SizedBox(
      height: 40,
      child: TextField(
        controller: searchController,
        onChanged: onSearchChanged,
        style: theme.textTheme.bodySmall,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
          ),
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () {
                    searchController.clear();
                    onSearchChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          isDense: true,
        ),
      ),
    );
  }

  Widget _idInput(ThemeData theme, bool isDark) {
    return Form(
      key: formKey,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextFormField(
                controller: idController,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  hintText: 'YouTube ID (npr. H-p2Hl6x7I0)',
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  prefixIcon: const Icon(Icons.ondemand_video_outlined,
                      size: 18),
                  isDense: true,
                ),
                textInputAction: TextInputAction.go,
                onFieldSubmitted: (_) => onManualOpen(),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Unesi ID' : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 42,
            child: FilledButton(
              onPressed: onManualOpen,
              style: FilledButton.styleFrom(
                backgroundColor: _croBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Icon(Icons.play_arrow, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shuffleRow(ThemeData theme) {
    return Row(
      mainAxisAlignment:
          isMobile ? MainAxisAlignment.center : MainAxisAlignment.end,
      children: [
        _viewModeToggle(theme),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onShuffle,
          icon: const Icon(Icons.shuffle, size: 18),
          tooltip: 'Promijesaj redoslijed',
          style: IconButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            padding: const EdgeInsets.all(6),
            minimumSize: const Size(32, 32),
          ),
        ),
      ],
    );
  }

  Widget _viewModeToggle(ThemeData theme) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleButton(
            theme: theme,
            icon: Icons.desktop_windows,
            label: 'Detaljno',
            isActive: !simpleMode,
            onTap: () => onSimpleModeChanged(false),
          ),
          _toggleButton(
            theme: theme,
            icon: Icons.phone_android,
            label: 'Jednostavno',
            isActive: simpleMode,
            onTap: () => onSimpleModeChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isActive
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid card for desktop/tablet — two layout modes:
/// BANNER (cover w!=h): cover image at real aspect ratio (530px logical = 1060/2),
///   text underneath.
/// SQUARE (cover w==h or missing): avatar 265px left, text right.
/// Both with 2px inverted border.
class _ChannelGridCard extends StatelessWidget {
  final ChannelSummary channel;
  final int index;
  final VoidCallback onTap;

  const _ChannelGridCard({
    required this.channel,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.onSurface.withAlpha(40);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 2),
      ),
      child: InkWell(
        onTap: onTap,
        child: channel.hasBannerCover
            ? _buildBannerLayout(theme)
            : _buildSquareLayout(theme),
      ),
    );
  }

  /// BANNER layout: cover at native aspect ratio (530px logical width),
  /// then info row underneath.
  Widget _buildBannerLayout(ThemeData theme) {
    final dim = channel.avatarCoverDimensions!;
    final scoreColor =
        MagisteriumSection.scoreColor(channel.avgMagisteriumScore);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover at real aspect ratio (1060x175 → ~6:1)
        AspectRatio(
          aspectRatio: dim.aspectRatio,
          child: Image.network(
            channel.avatarCover!,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (c, e, s) => Container(
              color: theme.colorScheme.primaryContainer.withAlpha(60),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Square avatar (90px logical = 180px at 2x)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: channel.avatarSquare != null
                    ? Image.network(
                        channel.avatarSquare!,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) =>
                            _avatarPlaceholder(theme, 90),
                      )
                    : _avatarPlaceholder(theme, 90),
              ),
              const SizedBox(width: 10),
              Expanded(child: _infoColumn(theme)),
              if (channel.avgMagisteriumScore != null)
                _scoreBadge(scoreColor, channel.avgMagisteriumScore!),
            ],
          ),
        ),
      ],
    );
  }

  /// SQUARE layout: big avatar left (265px logical = 530/2 for 2x crisp),
  /// text right.
  Widget _buildSquareLayout(ThemeData theme) {
    final scoreColor =
        MagisteriumSection.scoreColor(channel.avgMagisteriumScore);
    const avatarSize = 178.0; // matches banner card total height (cover ~88 + avatar 90)

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: channel.avatarSquare != null
                ? Image.network(
                    channel.avatarSquare!,
                    width: avatarSize,
                    height: avatarSize,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                        _avatarPlaceholder(theme, avatarSize),
                  )
                : _avatarPlaceholder(theme, avatarSize),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoColumn(theme),
                if (channel.avgMagisteriumScore != null) ...[
                  const SizedBox(height: 8),
                  _scoreBadge(scoreColor, channel.avgMagisteriumScore!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoColumn(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            channel.name,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${channel.videoCount} epizoda  •  ${channel.durationDisplay}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );

  static Widget _scoreBadge(Color color, int score) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.church, size: 12, color: color),
            const SizedBox(width: 3),
            Text(
              '$score',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      );

  static Widget _avatarPlaceholder(ThemeData theme, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(size > 60 ? 14 : 10),
        ),
        child: Icon(Icons.podcasts,
            size: size * 0.4, color: theme.colorScheme.onPrimaryContainer),
      );
}

/// List card for mobile — horizontal avatar + info.
class _ChannelListCard extends StatelessWidget {
  final ChannelSummary channel;
  final VoidCallback onTap;

  const _ChannelListCard({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreColor =
        MagisteriumSection.scoreColor(channel.avgMagisteriumScore);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: channel.avatarSquare != null
                    ? Image.network(
                        channel.avatarSquare!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) =>
                            _ChannelGridCard._avatarPlaceholder(theme, 56),
                      )
                    : _ChannelGridCard._avatarPlaceholder(theme, 56),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${channel.videoCount} epizoda  •  ${channel.durationDisplay}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (channel.avgMagisteriumScore != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scoreColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scoreColor.withAlpha(80)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.church, size: 12, color: scoreColor),
                      const SizedBox(width: 3),
                      Text(
                        '${channel.avgMagisteriumScore}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: scoreColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: Video grid / list (responsive)
// ---------------------------------------------------------------------------

class _VideoGridView extends StatelessWidget {
  final Future<ChannelDetail> channelFuture;
  final String? channelName;
  final String channelId;
  final void Function(String name) onResolvedName;
  final VoidCallback onBack;
  final void Function(String videoId) onVideoTap;

  const _VideoGridView({
    required this.channelFuture,
    this.channelName,
    required this.channelId,
    required this.onResolvedName,
    required this.onBack,
    required this.onVideoTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Natrag',
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              Text(
                channelName ?? channelId.replaceAll('_', ' '),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<ChannelDetail>(
            future: channelFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Greska: ${snap.error}'));
              }
              final detail = snap.data!;
              if (detail.name != channelName) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  onResolvedName(detail.name);
                });
              }
              return _ResponsiveVideoList(
                videos: detail.videos,
                onVideoTap: onVideoTap,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ResponsiveVideoList extends StatelessWidget {
  final List<ChannelVideo> videos;
  final void Function(String videoId) onVideoTap;

  const _ResponsiveVideoList({
    required this.videos,
    required this.onVideoTap,
  });

  static const double _maxCardWidth = 300;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 600) {
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            itemCount: videos.length,
            itemBuilder: (context, i) => _VideoCard(
              video: videos[i],
              onTap: () => onVideoTap(videos[i].id),
            ),
          );
        }
        final availableWidth = width - 32;
        final columns = (availableWidth / _maxCardWidth).floor().clamp(2, 99);
        final cardWidth = (availableWidth - (columns - 1) * 12) / columns;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: videos
                .map((v) => SizedBox(
                      width: cardWidth,
                      child: _VideoGridCard(
                        video: v,
                        onTap: () => onVideoTap(v.id),
                      ),
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

class _VideoCard extends StatelessWidget {
  final ChannelVideo video;
  final VoidCallback onTap;

  const _VideoCard({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasArticle = video.pipeline?.hasArticle ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: video.thumbnail != null
                    ? Image.network(
                        video.thumbnail!,
                        width: 120,
                        height: 68,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) =>
                            _placeholder(theme, 120, 68),
                      )
                    : _placeholder(theme, 120, 68),
              ),
              const SizedBox(width: 12),
              Expanded(child: _videoMeta(theme, video, hasArticle)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoGridCard extends StatelessWidget {
  final ChannelVideo video;
  final VoidCallback onTap;

  const _VideoGridCard({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasArticle = video.pipeline?.hasArticle ?? false;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: video.thumbnail != null
                  ? Image.network(
                      video.thumbnail!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (c, e, s) => _placeholder(theme),
                    )
                  : _placeholder(theme),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: _videoMeta(theme, video, hasArticle),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

Widget _placeholder(ThemeData theme, [double? w, double? h]) => Container(
      width: w,
      height: h,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.ondemand_video,
            color: theme.colorScheme.onSurfaceVariant),
      ),
    );

Widget _videoMeta(ThemeData theme, ChannelVideo video, bool hasArticle) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          video.displayTitle,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (video.date != null)
              _metaChip(theme, Icons.calendar_today, video.date!),
            if (video.durationDisplay != null)
              _metaChip(theme, Icons.schedule, video.durationDisplay!),
            if (video.views != null && video.views! > 0)
              _metaChip(theme, Icons.visibility, _formatCount(video.views!)),
          ],
        ),
        const SizedBox(height: 4),
        if (video.speakers.isNotEmpty)
          Text(
            video.speakers.join(', '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (video.magisteriumScore != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: MagisteriumSection.scoreColor(video.magisteriumScore)
                      .withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color:
                          MagisteriumSection.scoreColor(video.magisteriumScore)
                              .withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.church,
                        size: 11,
                        color: MagisteriumSection.scoreColor(
                            video.magisteriumScore)),
                    const SizedBox(width: 3),
                    Text(
                      '${video.magisteriumScore}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: MagisteriumSection.scoreColor(
                            video.magisteriumScore),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (!hasArticle)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'U obradi',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );

Widget _metaChip(ThemeData theme, IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

String _formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

/// Search result card for a video found across all channels.
class _VideoSearchCard extends StatelessWidget {
  final ChannelVideo video;
  final String channelName;
  final VoidCallback onTap;

  const _VideoSearchCard({
    required this.video,
    required this.channelName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: video.thumbnail != null
                    ? Image.network(
                        video.thumbnail!,
                        width: 120,
                        height: 68,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Container(
                          width: 120,
                          height: 68,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.ondemand_video),
                        ),
                      )
                    : Container(
                        width: 120,
                        height: 68,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.ondemand_video),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.displayTitle,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      channelName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (video.date != null) ...[
                          Icon(Icons.calendar_today,
                              size: 11,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text(
                            video.date!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (video.durationDisplay != null) ...[
                          Icon(Icons.schedule,
                              size: 11,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text(
                            video.durationDisplay!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
