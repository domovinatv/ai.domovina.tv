import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/speaker_timeline.dart';
import '../models/podcast_summary.dart';

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
  final SpeakerTimeline? speakerTimeline;
  final List<SummarySpeaker> speakers;
  final double? width;
  final void Function(Duration position)? onSeek;

  const VideoPanel({
    super.key,
    required this.player,
    required this.controller,
    required this.chapters,
    this.activeTimestamp,
    required this.onChapterTap,
    required this.totalDurationSeconds,
    this.speakerTimeline,
    this.speakers = const [],
    this.width = 360,
    this.onSeek,
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
    // Inicijaliziraj iz trenutnog stanja playera (bitno kad se widget
    // rekreira, npr. sidebar → EndDrawer pri resize-u)
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _playing = widget.player.state.playing;
    if (_duration.inMilliseconds > 0) {
      _sliderValue = _position.inMilliseconds / _duration.inMilliseconds;
    }

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

  /// Boje govornika — gradimo po redoslijedu iz speakers liste.
  Map<String, Color> _speakerColors(ThemeData theme) {
    final palette = [
      theme.colorScheme.primary,
      theme.colorScheme.tertiary,
      theme.colorScheme.secondary,
      theme.colorScheme.error,
    ];
    final map = <String, Color>{};
    for (var i = 0; i < widget.speakers.length; i++) {
      map[widget.speakers[i].id] = palette[i % palette.length];
    }
    return map;
  }

  SummarySpeaker? _currentSpeaker() {
    final timeline = widget.speakerTimeline;
    if (timeline == null) return null;
    final id = timeline.speakerAt(_position);
    if (id == null) return null;
    for (final s in widget.speakers) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : widget.totalDurationSeconds * 1000;
    final colors = _speakerColors(theme);
    final speaker = _currentSpeaker();

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: widget.width != null
            ? Border(
                left: BorderSide(color: theme.colorScheme.outlineVariant),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video display (16:9)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: MaterialDesktopVideoControlsTheme(
                normal: const MaterialDesktopVideoControlsThemeData(),
                fullscreen: MaterialDesktopVideoControlsThemeData(
                  topButtonBar: [
                    if (widget.speakerTimeline != null)
                      _FullscreenSpeakerLabel(
                        player: widget.player,
                        speakerTimeline: widget.speakerTimeline!,
                        speakers: widget.speakers,
                        speakerColors: colors,
                      ),
                  ],
                ),
                child: Video(controller: widget.controller),
              ),
            ),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              children: [
                // Speaker timeline bar
                if (widget.speakerTimeline != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LayoutBuilder(builder: (context, constraints) {
                        return SizedBox(
                          height: 6,
                          width: constraints.maxWidth,
                          child: CustomPaint(
                            painter: _SpeakerBarPainter(
                              segments: widget.speakerTimeline!.segments,
                              totalMs: totalMs,
                              colors: colors,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                // Seek bar s chapter markerima
                _SeekBar(
                  value: _sliderValue,
                  chapters: widget.chapters,
                  totalMs: totalMs,
                  onChangeStart: (_) => setState(() => _seeking = true),
                  onChanged: (v) => setState(() => _sliderValue = v),
                  onChangeEnd: (v) async {
                    final ms = (v * totalMs).round();
                    final dur = Duration(milliseconds: ms);
                    await widget.player.seek(dur);
                    widget.onSeek?.call(dur);
                    if (mounted) setState(() => _seeking = false);
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
                      tooltip: _playing ? 'Pauziraj' : 'Reproduciraj',
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

                // Trenutni govornik
                if (speaker != null)
                  _CurrentSpeakerRow(
                    speaker: speaker,
                    color: colors[speaker.id] ?? theme.colorScheme.outline,
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
                  onTap: () => widget.onChapterTap(ch.timestamp),
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

class _SpeakerBarPainter extends CustomPainter {
  final List<SpeakerSegment> segments;
  final int totalMs;
  final Map<String, Color> colors;

  const _SpeakerBarPainter({
    required this.segments,
    required this.totalMs,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalMs <= 0) return;
    for (final seg in segments) {
      final x1 = seg.startMs / totalMs * size.width;
      final x2 = seg.endMs / totalMs * size.width;
      final color = colors[seg.speakerId] ?? const Color(0x40808080);
      canvas.drawRect(
        Rect.fromLTWH(x1, 0, (x2 - x1).clamp(0.5, size.width), size.height),
        Paint()..color = color.withAlpha(180),
      );
    }
  }

  @override
  bool shouldRepaint(_SpeakerBarPainter old) =>
      old.segments != segments || old.totalMs != totalMs;
}

// ---------------------------------------------------------------------------

class _CurrentSpeakerRow extends StatelessWidget {
  final SummarySpeaker speaker;
  final Color color;

  const _CurrentSpeakerRow({
    required this.speaker,
    required this.color,
  });

  String get _initials {
    final parts = speaker.suggestedName.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return speaker.suggestedName.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color, width: 1.5),
            ),
            child: Center(
              child: Text(
                _initials,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  speaker.suggestedName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  speaker.role,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _FullscreenSpeakerLabel extends StatelessWidget {
  final Player player;
  final SpeakerTimeline speakerTimeline;
  final List<SummarySpeaker> speakers;
  final Map<String, Color> speakerColors;

  const _FullscreenSpeakerLabel({
    required this.player,
    required this.speakerTimeline,
    required this.speakers,
    required this.speakerColors,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final speakerId = speakerTimeline.speakerAt(pos);
        if (speakerId == null) return const SizedBox.shrink();

        SummarySpeaker? speaker;
        for (final s in speakers) {
          if (s.id == speakerId) {
            speaker = s;
            break;
          }
        }
        if (speaker == null) return const SizedBox.shrink();

        final color = speakerColors[speakerId] ?? Colors.white;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                speaker.suggestedName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                speaker.role,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
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
