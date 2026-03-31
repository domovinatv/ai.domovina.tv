import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show appVersion;
import '../models/channel_index.dart';
import '../models/channel_detail.dart';
import '../services/data_service.dart';
import '../services/update_notifier.dart';
import '../widgets/magisterium_section.dart';

const _channelOrderKey = 'channel_order';

class HomeScreen extends StatefulWidget {
  final String? initialChannelId;

  const HomeScreen({super.key, this.initialChannelId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _idController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late Future<ChannelIndex> _indexFuture;
  String? _selectedChannelId;
  String? _selectedChannelName;
  Future<ChannelDetail>? _channelFuture;

  // Ordered channel list (shuffled once, persisted)
  List<ChannelSummary>? _orderedChannels;

  @override
  void initState() {
    super.initState();
    _indexFuture = ChannelService.loadIndex();
    if (widget.initialChannelId != null) {
      _selectedChannelId = widget.initialChannelId;
      _channelFuture =
          ChannelService.loadChannel(widget.initialChannelId!);
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  /// Apply saved order or shuffle for first-time visitors, then persist.
  Future<List<ChannelSummary>> _applyOrder(
      List<ChannelSummary> channels) async {
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList(_channelOrderKey);

    if (savedOrder != null && savedOrder.isNotEmpty) {
      // Reorder channels by saved ID order, append any new channels at end
      final byId = {for (final ch in channels) ch.id: ch};
      final ordered = <ChannelSummary>[];
      for (final id in savedOrder) {
        final ch = byId.remove(id);
        if (ch != null) ordered.add(ch);
      }
      ordered.addAll(byId.values); // new channels not in saved order
      return ordered;
    }

    // First visit — shuffle and save
    final shuffled = List<ChannelSummary>.from(channels)..shuffle(Random());
    await prefs.setStringList(
        _channelOrderKey, shuffled.map((c) => c.id).toList());
    return shuffled;
  }

  Future<void> _shuffle() async {
    if (_orderedChannels == null) return;
    final shuffled = List<ChannelSummary>.from(_orderedChannels!)
      ..shuffle(Random());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _channelOrderKey, shuffled.map((c) => c.id).toList());
    setState(() => _orderedChannels = shuffled);
  }

  void _selectChannel(ChannelSummary channel) {
    final slug = channel.id.replaceAll('_', '-');
    Navigator.of(context).pushNamed('/c/$slug');
  }

  void _back() {
    Navigator.of(context).pushNamed('/');
  }

  void _openVideo(String videoId) {
    Navigator.of(context).pushNamed('/v/$videoId');
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
      body: isChannel
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
              onChannelsLoaded: (channels) async {
                final ordered = await _applyOrder(channels);
                if (mounted) setState(() => _orderedChannels = ordered);
              },
              onChannelTap: _selectChannel,
              onShuffle: _shuffle,
              idController: _idController,
              formKey: _formKey,
              onManualOpen: _openManual,
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
  final Future<void> Function(List<ChannelSummary>) onChannelsLoaded;
  final void Function(ChannelSummary) onChannelTap;
  final VoidCallback onShuffle;
  final TextEditingController idController;
  final GlobalKey<FormState> formKey;
  final VoidCallback onManualOpen;

  const _ChannelGridView({
    required this.indexFuture,
    required this.orderedChannels,
    required this.onChannelsLoaded,
    required this.onChannelTap,
    required this.onShuffle,
    required this.idController,
    required this.formKey,
    required this.onManualOpen,
  });

  static const double _maxCardWidth = 280;

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

        final channels = orderedChannels!;

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isMobile = width < 600;

            return CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
                    child: Column(
                      children: [
                        Text(
                          'Domovina.ai',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${channels.length} kanala',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: onShuffle,
                              icon: const Icon(Icons.shuffle, size: 20),
                              tooltip: 'Promijesaj redoslijed',
                              style: IconButton.styleFrom(
                                foregroundColor:
                                    theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),

                // Channel grid/list
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

                // Footer: manual ID + version
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                        child: Column(
                          children: [
                            Divider(color: theme.colorScheme.outlineVariant),
                            const SizedBox(height: 16),
                            Text(
                              'Ili unesi YouTube ID direktno',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Form(
                              key: formKey,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: idController,
                                      decoration: const InputDecoration(
                                        labelText: 'YouTube ID',
                                        hintText: 'npr. H-p2Hl6x7I0',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(
                                            Icons.ondemand_video_outlined),
                                        isDense: true,
                                      ),
                                      textInputAction: TextInputAction.go,
                                      onFieldSubmitted: (_) => onManualOpen(),
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                              ? 'Unesi ID'
                                              : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: onManualOpen,
                                    child: const Icon(Icons.play_arrow),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            Center(
                              child: GestureDetector(
                                onTap: kIsWeb ? hardReload : null,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'v$appVersion',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: theme
                                            .colorScheme.onSurfaceVariant
                                            .withAlpha(100),
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    if (kIsWeb) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.refresh,
                                        size: 14,
                                        color: theme
                                            .colorScheme.onSurfaceVariant
                                            .withAlpha(100),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
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
      children: channels
          .map((ch) => SizedBox(
                width: cardWidth,
                child: _ChannelGridCard(
                  channel: ch,
                  onTap: () => onChannelTap(ch),
                ),
              ))
          .toList(),
    );
  }
}

/// Grid card for desktop/tablet — vertical avatar + info.
class _ChannelGridCard extends StatelessWidget {
  final ChannelSummary channel;
  final VoidCallback onTap;

  const _ChannelGridCard({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreColor =
        MagisteriumSection.scoreColor(channel.avgMagisteriumScore);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover/avatar banner
            AspectRatio(
              aspectRatio: 16 / 9,
              child: channel.avatarCover != null
                  ? Image.network(
                      channel.avatarCover!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (c, e, s) => _coverPlaceholder(theme),
                    )
                  : _coverPlaceholder(theme),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Small avatar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: channel.avatarSquare != null
                        ? Image.network(
                            channel.avatarSquare!,
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) =>
                                _avatarPlaceholder(theme),
                          )
                        : _avatarPlaceholder(theme),
                  ),
                  const SizedBox(width: 10),
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
                  if (channel.avgMagisteriumScore != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _coverPlaceholder(ThemeData theme) => Container(
        color: theme.colorScheme.primaryContainer.withAlpha(60),
        child: Center(
          child: Icon(Icons.podcasts,
              size: 32, color: theme.colorScheme.onPrimaryContainer),
        ),
      );

  static Widget _avatarPlaceholder(ThemeData theme) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.podcasts,
            size: 18, color: theme.colorScheme.onPrimaryContainer),
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
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) =>
                            _ChannelGridCard._avatarPlaceholder(theme),
                      )
                    : _ChannelGridCard._avatarPlaceholder(theme),
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
