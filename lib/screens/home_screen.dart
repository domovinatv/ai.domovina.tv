import 'package:flutter/material.dart';
import '../models/channel_index.dart';
import '../models/channel_detail.dart';
import '../services/data_service.dart';
import '../widgets/magisterium_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _idController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late Future<ChannelIndex> _indexFuture;
  ChannelSummary? _selectedChannel;
  Future<ChannelDetail>? _channelFuture;

  @override
  void initState() {
    super.initState();
    _indexFuture = ChannelService.loadIndex();
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  void _selectChannel(ChannelSummary channel) {
    setState(() {
      _selectedChannel = channel;
      _channelFuture = ChannelService.loadChannel(channel.id);
    });
  }

  void _back() {
    setState(() {
      _selectedChannel = null;
      _channelFuture = null;
    });
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

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _selectedChannel != null
              ? _VideoListView(
                  channelFuture: _channelFuture!,
                  channelName: _selectedChannel!.name,
                  onBack: _back,
                  onVideoTap: _openVideo,
                )
              : _ChannelListView(
                  indexFuture: _indexFuture,
                  onChannelTap: _selectChannel,
                  idController: _idController,
                  formKey: _formKey,
                  onManualOpen: _openManual,
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Channel selection
// ---------------------------------------------------------------------------

class _ChannelListView extends StatelessWidget {
  final Future<ChannelIndex> indexFuture;
  final void Function(ChannelSummary) onChannelTap;
  final TextEditingController idController;
  final GlobalKey<FormState> formKey;
  final VoidCallback onManualOpen;

  const _ChannelListView({
    required this.indexFuture,
    required this.onChannelTap,
    required this.idController,
    required this.formKey,
    required this.onManualOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 32),
        Text(
          'Domovina.ai',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Odaberi kanal',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Channel cards
        FutureBuilder<ChannelIndex>(
          future: indexFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Greska pri ucitavanju kanala:\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }
            final channels = snap.data!.channels;
            return Column(
              children: channels
                  .map((ch) => _ChannelCard(
                        channel: ch,
                        onTap: () => onChannelTap(ch),
                      ))
                  .toList(),
            );
          },
        ),

        // Manual ID fallback
        const SizedBox(height: 32),
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
                    prefixIcon: Icon(Icons.ondemand_video_outlined),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.go,
                  onFieldSubmitted: (_) => onManualOpen(),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Unesi ID' : null,
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
      ],
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final ChannelSummary channel;
  final VoidCallback onTap;

  const _ChannelCard({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreColor =
        MagisteriumSection.scoreColor(channel.avgMagisteriumScore);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Channel icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.podcasts,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${channel.videoCount} epizoda  •  ${channel.durationDisplay}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (channel.latestVideo != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Najnovije: ${channel.latestVideo!.title}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Score + arrow
              if (channel.avgMagisteriumScore != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scoreColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scoreColor.withAlpha(80)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.church, size: 14, color: scoreColor),
                      const SizedBox(width: 4),
                      Text(
                        '${channel.avgMagisteriumScore}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: scoreColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: Video selection
// ---------------------------------------------------------------------------

class _VideoListView extends StatelessWidget {
  final Future<ChannelDetail> channelFuture;
  final String channelName;
  final VoidCallback onBack;
  final void Function(String videoId) onVideoTap;

  const _VideoListView({
    required this.channelFuture,
    required this.channelName,
    required this.onBack,
    required this.onVideoTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Header with back button
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
                channelName,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Video list
        Expanded(
          child: FutureBuilder<ChannelDetail>(
            future: channelFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Text('Greska: ${snap.error}'),
                );
              }
              final videos = snap.data!.videos;
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                itemCount: videos.length,
                itemBuilder: (context, i) => _VideoCard(
                  video: videos[i],
                  onTap: () => onVideoTap(videos[i].id),
                ),
              );
            },
          ),
        ),
      ],
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
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: video.thumbnail != null
                    ? Image.network(
                        video.thumbnail!,
                        width: 120,
                        height: 68,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => _thumbnailPlaceholder(theme),
                      )
                    : _thumbnailPlaceholder(theme),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.displayTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Metadata row
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (video.date != null)
                          _metaChip(theme, Icons.calendar_today, video.date!),
                        if (video.durationDisplay != null)
                          _metaChip(
                              theme, Icons.schedule, video.durationDisplay!),
                        if (video.views != null && video.views! > 0)
                          _metaChip(theme, Icons.visibility,
                              _formatCount(video.views!)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Speakers
                    if (video.speakers.isNotEmpty)
                      Text(
                        video.speakers
                            .map((s) => s.suggestedName)
                            .join(', '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    // Pipeline / score badges
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (video.magisteriumScore != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: MagisteriumSection.scoreColor(
                                      video.magisteriumScore)
                                  .withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: MagisteriumSection.scoreColor(
                                          video.magisteriumScore)
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnailPlaceholder(ThemeData theme) => Container(
        width: 120,
        height: 68,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.ondemand_video,
            color: theme.colorScheme.onSurfaceVariant),
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

  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}
