import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Marker za jedno poglavlje u video playeru (timestamp + label)
class VideoChapterMark {
  final Duration position;
  final String timestamp; // "HH:MM:SS" — kao u article.json
  final String label;

  const VideoChapterMark({
    required this.position,
    required this.timestamp,
    required this.label,
  });
}

/// Fiksni video panel — prikazuje player s kontrolama i chapter markerima.
/// Player i VideoController su vanjski (owned by _EpisodeContentState).
class VideoPanel extends StatefulWidget {
  final Player player;
  final VideoController controller;
  final List<VideoChapterMark> chapters;
  final String? activeTimestamp;
  final void Function(String timestamp) onChapterTap;
  final int totalDurationSeconds;

  const VideoPanel({
    super.key,
    required this.player,
    required this.controller,
    required this.chapters,
    this.activeTimestamp,
    required this.onChapterTap,
    required this.totalDurationSeconds,
  });

  @override
  State<VideoPanel> createState() => _VideoPanelState();
}

class _VideoPanelState extends State<VideoPanel> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _seeking = false;
  double _sliderValue = 0;

  @override
  void initState() {
    super.initState();
    widget.player.stream.position.listen((p) {
      if (!_seeking && mounted) {
        setState(() {
          _position = p;
          _sliderValue = _duration.inMilliseconds > 0
              ? p.inMilliseconds / _duration.inMilliseconds
              : 0;
        });
      }
    });
    widget.player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    widget.player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
    });
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : widget.totalDurationSeconds * 1000;

    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video display (16:9)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: Video(controller: widget.controller),
            ),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              children: [
                // Seek bar s chapter markerima
                _SeekBar(
                  value: _sliderValue,
                  chapters: widget.chapters,
                  totalMs: totalMs,
                  onChangeStart: (_) => setState(() => _seeking = true),
                  onChanged: (v) => setState(() => _sliderValue = v),
                  onChangeEnd: (v) {
                    final ms = (v * totalMs).round();
                    widget.player.seek(Duration(milliseconds: ms));
                    setState(() => _seeking = false);
                  },
                ),

                // Vrijeme
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fmt(_position),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _fmt(_duration),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),

                // Play/Pause + skip buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10),
                      onPressed: () => widget.player
                          .seek(_position - const Duration(seconds: 10)),
                      tooltip: '-10s',
                    ),
                    IconButton(
                      iconSize: 40,
                      icon: Icon(_playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled),
                      color: theme.colorScheme.primary,
                      onPressed: () =>
                          _playing ? widget.player.pause() : widget.player.play(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_10),
                      onPressed: () => widget.player
                          .seek(_position + const Duration(seconds: 10)),
                      tooltip: '+10s',
                    ),
                  ],
                ),
              ],
            ),
          ),

          Divider(height: 1, color: theme.colorScheme.outlineVariant),

          // Chapter lista — scrollable
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'Poglavlja',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: widget.chapters.length,
              itemBuilder: (context, i) {
                final ch = widget.chapters[i];
                final isActive = ch.timestamp == widget.activeTimestamp;
                return _ChapterListItem(
                  chapter: ch,
                  isActive: isActive,
                  onTap: () {
                    widget.player.seek(ch.position);
                    widget.player.play();
                    widget.onChapterTap(ch.timestamp);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SeekBar extends StatelessWidget {
  final double value;
  final List<VideoChapterMark> chapters;
  final int totalMs;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SeekBar({
    required this.value,
    required this.chapters,
    required this.totalMs,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Chapter markers (renderiraju se ispod Slidera)
        LayoutBuilder(builder: (context, constraints) {
          return SizedBox(
            height: 24,
            width: constraints.maxWidth,
            child: CustomPaint(
              painter: _ChapterMarkerPainter(
                chapters: chapters,
                totalMs: totalMs,
                color: theme.colorScheme.primary.withAlpha(120),
              ),
            ),
          );
        }),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChangeStart: onChangeStart,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

class _ChapterMarkerPainter extends CustomPainter {
  final List<VideoChapterMark> chapters;
  final int totalMs;
  final Color color;

  const _ChapterMarkerPainter({
    required this.chapters,
    required this.totalMs,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalMs <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final ch in chapters) {
      final x = ch.position.inMilliseconds / totalMs * size.width;
      canvas.drawLine(
        Offset(x, size.height * 0.1),
        Offset(x, size.height * 0.9),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ChapterMarkerPainter old) =>
      old.chapters != chapters || old.totalMs != totalMs;
}

// ---------------------------------------------------------------------------

class _ChapterListItem extends StatelessWidget {
  final VideoChapterMark chapter;
  final bool isActive;
  final VoidCallback onTap;

  const _ChapterListItem({
    required this.chapter,
    required this.isActive,
    required this.onTap,
  });

  String get _shortTs {
    final parts = chapter.timestamp.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      if (h == 0) return '${parts[1]}:${parts[2]}';
      return '$h:${parts[1]}:${parts[2]}';
    }
    return chapter.timestamp;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: isActive
            ? BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(120),
                border: Border(
                  left: BorderSide(
                      color: theme.colorScheme.primary, width: 3),
                ),
              )
            : null,
        padding: EdgeInsets.fromLTRB(isActive ? 9 : 12, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.play_arrow,
              size: 14,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              _shortTs,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                chapter.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isActive
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
