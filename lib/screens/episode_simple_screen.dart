import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/background_audio.dart';
import '../services/data_service.dart';

/// Pojednostavljeni mobile-first ekran za reprodukciju podcast epizode.
/// Optimiziran za slušanje u autu — 3 taba: Player, Poglavlja, Info.
class EpisodeSimpleScreen extends StatefulWidget {
  final String youtubeId;

  const EpisodeSimpleScreen({super.key, required this.youtubeId});

  @override
  State<EpisodeSimpleScreen> createState() => _EpisodeSimpleScreenState();
}

class _EpisodeSimpleScreenState extends State<EpisodeSimpleScreen> {
  EpisodeData? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await EpisodeData.load(youtubeId: widget.youtubeId);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) {
      return _SimpleEpisodeContent(data: _data!);
    }

    if (_error != null) {
      final notFound = _error is VideoNotFoundException;
      final theme = Theme.of(context);
      return Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    notFound ? Icons.video_file_outlined : Icons.error_outline,
                    size: 48,
                    color: notFound ? null : Colors.red,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    notFound
                        ? 'Epizoda "${widget.youtubeId}" nije pronađena.'
                        : 'Greška pri učitavanju:\n$_error',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Natrag'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Loading
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

// ---------------------------------------------------------------------------
// Content - 3-tab layout
// ---------------------------------------------------------------------------

class _SimpleEpisodeContent extends StatefulWidget {
  final EpisodeData data;

  const _SimpleEpisodeContent({required this.data});

  @override
  State<_SimpleEpisodeContent> createState() => _SimpleEpisodeContentState();
}

class _SimpleEpisodeContentState extends State<_SimpleEpisodeContent> {
  int _tabIndex = 0;

  // Video
  Player? _player;
  VideoController? _videoController;
  bool _videoReady = false;
  StreamSubscription<Duration>? _positionSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  /// Flat lista svih poglavlja iz outline-a za brz pristup.
  late final List<({String timestamp, String topic, int totalSeconds})>
      _chapters;

  @override
  void initState() {
    super.initState();
    _chapters = _buildChapters();
    _initVideo();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    BackgroundAudio.instance.detach();
    _player?.dispose();
    super.dispose();
  }

  List<({String timestamp, String topic, int totalSeconds})> _buildChapters() {
    final list =
        <({String timestamp, String topic, int totalSeconds})>[];
    for (final iter in widget.data.outline.iterations) {
      for (final ch in iter.chapters) {
        list.add((
          timestamp: ch.timestamp,
          topic: ch.topic,
          totalSeconds: ch.totalSeconds,
        ));
      }
    }
    list.sort((a, b) => a.totalSeconds.compareTo(b.totalSeconds));
    return list;
  }

  Future<void> _initVideo() async {
    try {
      final player = Player();
      final controller = VideoController(player);

      if (kIsWeb) {
        await player.open(Media(widget.data.videoUri), play: false);
        try {
          await player.play();
        } catch (_) {
          await player.setVolume(0);
          await player.play();
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!player.state.playing) {
          await player.setVolume(0);
          await player.play();
        }
      } else {
        await player.open(Media(widget.data.videoUri), play: true);
      }

      _positionSub = player.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });

      if (mounted) {
        setState(() {
          _player = player;
          _videoController = controller;
          _videoReady = true;
        });

        // Background audio session — lock screen + notification na native.
        final summaryTitle = widget.data.summary.summary.titleHr;
        BackgroundAudio.instance.attach(
          player: player,
          title: summaryTitle.isNotEmpty ? summaryTitle : widget.data.info.title,
          artist: widget.data.info.channel,
          artUri: widget.data.info.thumbnail,
          duration: Duration(seconds: widget.data.info.duration),
        );
      }
    } catch (e) {
      debugPrint('SimpleEpisode: video init failed — $e');
    }
  }

  Future<void> _seekTo(int seconds) async {
    await _player?.seek(Duration(seconds: seconds));
    if (!(_player?.state.playing ?? false)) {
      await _player?.play();
    }
    // Switch to player tab after seeking
    if (_tabIndex != 0) {
      setState(() => _tabIndex = 0);
    }
  }

  /// Pronađi koji je chapter aktivan na temelju pozicije.
  int _activeChapterIndex() {
    int active = -1;
    final posSec = _position.inSeconds;
    for (int i = 0; i < _chapters.length; i++) {
      if (posSec >= _chapters[i].totalSeconds) {
        active = i;
      }
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Text(
          data.info.channel,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Switch to detailed view
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Detaljni prikaz',
            onPressed: () => context.go('/v/${data.youtubeId}'),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _PlayerTab(
            data: data,
            player: _player,
            videoController: _videoController,
            videoReady: _videoReady,
            position: _position,
            duration: _duration,
            isPlaying: _isPlaying,
            onPlayPause: () {
              if (_isPlaying) {
                _player?.pause();
              } else {
                _player?.play();
              }
            },
            onSeek: (d) => _player?.seek(d),
          ),
          _ChaptersTab(
            chapters: _chapters,
            activeIndex: _activeChapterIndex(),
            onChapterTap: (seconds) => _seekTo(seconds),
          ),
          _InfoTab(data: data),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle_filled),
            label: 'Player',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_outlined),
            selectedIcon: Icon(Icons.list),
            label: 'Poglavlja',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: 'Info',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Player
// ---------------------------------------------------------------------------

class _PlayerTab extends StatelessWidget {
  final EpisodeData data;
  final Player? player;
  final VideoController? videoController;
  final bool videoReady;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final void Function(Duration) onSeek;

  const _PlayerTab({
    required this.data,
    required this.player,
    required this.videoController,
    required this.videoReady,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSeek,
  });

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = data.info;
    final summary = data.summary.summary;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video player or thumbnail
          AspectRatio(
            aspectRatio: 16 / 9,
            child: videoReady && videoController != null
                ? Video(controller: videoController!)
                : Container(
                    color: Colors.black,
                    child: info.thumbnail.isNotEmpty
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.network(
                                info.thumbnail,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (c, e, s) => const SizedBox(),
                              ),
                              const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ],
                          )
                        : const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                  ),
          ),

          // Seek bar
          if (videoReady) ...[
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 16,
                ),
                activeTrackColor: theme.colorScheme.primary,
                inactiveTrackColor:
                    theme.colorScheme.primary.withAlpha(40),
                thumbColor: theme.colorScheme.primary,
              ),
              child: Slider(
                value: duration.inMilliseconds > 0
                    ? position.inMilliseconds
                        .clamp(0, duration.inMilliseconds)
                        .toDouble()
                    : 0,
                max: duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1,
                onChanged: (v) =>
                    onSeek(Duration(milliseconds: v.toInt())),
              ),
            ),

            // Time + controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    _formatDuration(position),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  // Rewind 15s
                  IconButton(
                    icon: const Icon(Icons.replay_10),
                    iconSize: 32,
                    onPressed: () => onSeek(
                      Duration(
                        seconds: (position.inSeconds - 10).clamp(0, 999999),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Play/Pause
                  IconButton.filled(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    iconSize: 40,
                    onPressed: onPlayPause,
                  ),
                  const SizedBox(width: 8),
                  // Forward 30s
                  IconButton(
                    icon: const Icon(Icons.forward_30),
                    iconSize: 32,
                    onPressed: () => onSeek(
                      Duration(seconds: position.inSeconds + 30),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDuration(duration),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Episode info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.titleHr.isNotEmpty ? summary.titleHr : info.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.podcasts,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        info.channel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      info.durationString,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (summary.speakers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: summary.speakers.map((s) {
                      return Chip(
                        avatar: Icon(
                          Icons.person,
                          size: 16,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        label: Text(
                          s.suggestedName,
                          style: const TextStyle(fontSize: 12),
                        ),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Chapters
// ---------------------------------------------------------------------------

class _ChaptersTab extends StatelessWidget {
  final List<({String timestamp, String topic, int totalSeconds})> chapters;
  final int activeIndex;
  final void Function(int seconds) onChapterTap;

  const _ChaptersTab({
    required this.chapters,
    required this.activeIndex,
    required this.onChapterTap,
  });

  String _formatTime(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (chapters.isEmpty) {
      return Center(
        child: Text(
          'Nema poglavlja za ovu epizodu.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: chapters.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: theme.colorScheme.outlineVariant.withAlpha(80),
      ),
      itemBuilder: (context, i) {
        final ch = chapters[i];
        final isActive = i == activeIndex;

        return ListTile(
          leading: Container(
            width: 56,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _formatTime(ch.totalSeconds),
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          title: Text(
            ch.topic,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            isActive ? Icons.play_arrow : Icons.chevron_right,
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
          onTap: () => onChapterTap(ch.totalSeconds),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3: Info
// ---------------------------------------------------------------------------

class _InfoTab extends StatelessWidget {
  final EpisodeData data;

  const _InfoTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = data.info;
    final summary = data.summary.summary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Title
        Text(
          summary.titleHr.isNotEmpty ? summary.titleHr : info.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Abstract
        if (summary.abstractHr.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              summary.abstractHr,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Key topics
        if (summary.keyTopics.isNotEmpty) ...[
          _SectionTitle(icon: Icons.topic, label: 'Ključne teme'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: summary.keyTopics.map((t) {
              return Chip(
                label: Text(t, style: const TextStyle(fontSize: 12)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // Key points
        if (summary.keyPoints.isNotEmpty) ...[
          _SectionTitle(icon: Icons.format_list_bulleted, label: 'Ključne točke'),
          const SizedBox(height: 8),
          ...summary.keyPoints.map((kp) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(
                        Icons.circle,
                        size: 6,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        kp,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 16),
        ],

        // Speakers
        if (summary.speakers.isNotEmpty) ...[
          _SectionTitle(icon: Icons.people, label: 'Govornici'),
          const SizedBox(height: 8),
          ...summary.speakers.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.person,
                        size: 18,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.suggestedName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (s.role.isNotEmpty)
                            Text(
                              s.role,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 16),
        ],

        // Metadata
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 8),
        _MetaRow(
          icon: Icons.calendar_today,
          label: 'Datum',
          value: _formatDate(info.uploadDate),
          theme: theme,
        ),
        _MetaRow(
          icon: Icons.schedule,
          label: 'Trajanje',
          value: info.durationString,
          theme: theme,
        ),
        _MetaRow(
          icon: Icons.visibility,
          label: 'Pregledi',
          value: _formatCount(info.viewCount),
          theme: theme,
        ),
        _MetaRow(
          icon: Icons.thumb_up,
          label: 'Lajkovi',
          value: _formatCount(info.likeCount),
          theme: theme,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _formatDate(String yyyymmdd) {
    if (yyyymmdd.length == 8) {
      return '${yyyymmdd.substring(6, 8)}.${yyyymmdd.substring(4, 6)}.${yyyymmdd.substring(0, 4)}.';
    }
    return yyyymmdd;
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
