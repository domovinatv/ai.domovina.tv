import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/data_service.dart';
import '../widgets/hero_section.dart';
import '../widgets/summary_section.dart';
import '../widgets/chapters_section.dart';
import '../widgets/article_section.dart';
import '../widgets/entities_section.dart';
import '../widgets/table_of_contents.dart';
import '../widgets/video_panel.dart';

class EpisodeScreen extends StatefulWidget {
  final String youtubeId;

  const EpisodeScreen({super.key, required this.youtubeId});

  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  late Future<EpisodeData> _future;

  @override
  void initState() {
    super.initState();
    _future = EpisodeData.load(youtubeId: widget.youtubeId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EpisodeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(
                      'Greška pri ucitavanju podataka:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return _EpisodeContent(data: snapshot.data!);
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _EpisodeContent extends StatefulWidget {
  final EpisodeData data;

  const _EpisodeContent({required this.data});

  @override
  State<_EpisodeContent> createState() => _EpisodeContentState();
}

class _EpisodeContentState extends State<_EpisodeContent> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();
  late final Map<String, GlobalKey> _sectionKeys;
  String? _activeTimestamp;

  // Video
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<Duration>? _positionSub;
  bool _videoReady = false;

  /// Sortirane sekcije kao (Duration, timestampString) za sync Video→Text
  late final List<({Duration dur, String ts})> _sortedSections;

  /// Chapters za VideoPanel
  late final List<VideoChapterMark> _videoChapters;

  /// Sprječava auto-scroll iz video listenera dok korisnik ručno scrolla
  DateTime? _lastManualScroll;

  /// Sprječava section flicker tijekom preroll seek-a (-2s)
  DateTime? _seekLock;

  @override
  void initState() {
    super.initState();

    _sectionKeys = {
      for (final iter in widget.data.article.iterations)
        for (final sec in iter.sections)
          sec.screenshotTimestamp: GlobalKey(),
    };

    _sortedSections = [
      for (final iter in widget.data.article.iterations)
        for (final sec in iter.sections)
          (dur: _parseDuration(sec.screenshotTimestamp), ts: sec.screenshotTimestamp),
    ]..sort((a, b) => a.dur.compareTo(b.dur));

    _videoChapters = _sortedSections
        .map((s) {
          final label = _subtitleForTimestamp(s.ts);
          return VideoChapterMark(
            position: s.dur,
            timestamp: s.ts,
            label: label,
          );
        })
        .toList();

    _scrollController.addListener(_onScroll);
    _initVideo();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _positionSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  // ---------- helpers -------------------------------------------------------

  Duration _parseDuration(String ts) {
    // "HH:MM:SS" → Duration
    final parts = ts.split(':').map(int.parse).toList();
    if (parts.length == 3) {
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    }
    return Duration.zero;
  }

  String _subtitleForTimestamp(String ts) {
    for (final iter in widget.data.article.iterations) {
      for (final sec in iter.sections) {
        if (sec.screenshotTimestamp == ts) return sec.subtitle;
      }
    }
    return ts;
  }

  // ---------- video ---------------------------------------------------------

  Future<void> _initVideo() async {
    final videoUri = widget.data.videoUri;
    if (videoUri == null) {
      debugPrint('Video: no videoUri resolved');
      return;
    }
    debugPrint('Video: opening $videoUri');

    try {
      final player = Player();
      final controller = VideoController(player);
      // Na webu: preglednici blokiraju autoplay s audiom, korisnik mora kliknuti play
      await player.open(Media(videoUri), play: !kIsWeb);

      _positionSub = player.stream.position.listen(_onVideoPosition);

      if (mounted) {
        setState(() {
          _player = player;
          _videoController = controller;
          _videoReady = true;
        });
        debugPrint('Video: ready');
      }
    } catch (e) {
      debugPrint('Video: init failed — $e');
    }
  }

  void _onVideoPosition(Duration pos) {
    // Preskoči section detekciju tijekom preroll seeka (-2s)
    final lock = _seekLock;
    if (lock != null &&
        DateTime.now().difference(lock) < const Duration(seconds: 3)) {
      return;
    }

    // Pronadji aktivnu sekciju: zadnja sekcija čiji timestamp <= pos
    String? newTs;
    for (final s in _sortedSections) {
      if (pos >= s.dur) {
        newTs = s.ts;
      } else {
        break;
      }
    }
    if (newTs == null || newTs == _activeTimestamp) return;

    // Postavi aktivni timestamp (ažurira TOC highlight)
    setState(() => _activeTimestamp = newTs!);

    // Auto-scroll teksta samo ako korisnik nije ručno scrollao zadnje 2 sekunde
    final lastScroll = _lastManualScroll;
    if (lastScroll == null ||
        DateTime.now().difference(lastScroll) >
            const Duration(seconds: 2)) {
      _scrollToSection(newTs);
    }
  }

  // ---------- scroll --------------------------------------------------------

  void _onScroll() {
    _lastManualScroll = DateTime.now();
    _updateActiveSectionFromScroll();
  }

  void _updateActiveSectionFromScroll() {
    for (final entry in _sectionKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final pos = box.localToGlobal(Offset.zero);
      final screenH = MediaQuery.sizeOf(context).height;
      if (pos.dy >= 0 && pos.dy < screenH * 0.4) {
        if (_activeTimestamp != entry.key) {
          setState(() => _activeTimestamp = entry.key);
        }
        return;
      }
    }
  }

  void _scrollToSection(String timestamp) {
    final key = _sectionKeys[timestamp];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
    }
  }

  /// Kad korisnik seekuje slider, uvijek scrollaj na ispravnu sekciju.
  void _onVideoSeek(Duration pos) {
    String? newTs;
    for (final s in _sortedSections) {
      if (pos >= s.dur) {
        newTs = s.ts;
      } else {
        break;
      }
    }
    if (newTs == null) return;
    setState(() => _activeTimestamp = newTs!);
    _scrollToSection(newTs);
  }

  /// Seek video na timestamp + play + scroll teksta.
  /// [preroll]: ako true, seekaj 2s prije za kontekst (samo video chapter lista).
  Future<void> _seekAndPlay(String timestamp, {bool preroll = false}) async {
    final dur = _parseDuration(timestamp);
    var seekTo = dur;
    if (preroll) {
      seekTo = dur - const Duration(seconds: 2);
      if (seekTo < Duration.zero) seekTo = Duration.zero;
      _seekLock = DateTime.now();
    }
    // Na webu, HTML5 video element zahtijeva da je video u playing stanju
    // prije nego što seek (currentTime) postavi poziciju ispravno.
    // Ako seek pozovemo na pauziranom/neučitanom videu, bude ignoriran.
    if (kIsWeb) {
      await _player?.play();
      await _player?.seek(seekTo);
    } else {
      await _player?.seek(seekTo);
      await _player?.play();
    }
    setState(() => _activeTimestamp = timestamp);
    _scrollToSection(timestamp);
  }

  void _drawerTap(String timestamp) {
    _scaffoldKey.currentState?.closeDrawer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seekAndPlay(timestamp);
    });
  }

  // ---------- build ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width > 900;
    final showVideo = _videoReady && width > 1100;

    final scrollBody = CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverAppBar(
          floating: true,
          snap: true,
          leading: isWide
              ? null
              : IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Sadržaj',
                  onPressed: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                ),
          automaticallyImplyLeading: false,
          title: Text(
            data.info.channel,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: _videoReady && !showVideo ? 4 : 16),
              child: Center(
                child: Text(
                  data.info.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (_videoReady && !showVideo)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: const Icon(Icons.ondemand_video),
                  tooltip: 'Video',
                  onPressed: () =>
                      _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ),
          ],
        ),
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HeroSection(
                    info: data.info,
                    summary: data.summary,
                    youtubeId: data.youtubeId,
                  ),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  SummarySection(summary: data.summary),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  ChaptersSection(outline: data.outline),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  ArticleSection(
                    article: data.article,
                    youtubeId: data.youtubeId,
                    sectionKeys: _sectionKeys,
                    onPlayTap: _videoReady ? _seekAndPlay : null,
                  ),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  EntitiesSection(summary: data.summary.summary),
                  _MetadataFooter(data: data),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    Widget body;
    if (showVideo) {
      // Desktop wide: TOC | content | video
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: data.article,
            activeTimestamp: _activeTimestamp,
            onSectionTap: _seekAndPlay,
          ),
          Expanded(child: scrollBody),
          VideoPanel(
            player: _player!,
            controller: _videoController!,
            chapters: _videoChapters,
            activeTimestamp: _activeTimestamp,
            onChapterTap: (ts) => _seekAndPlay(ts, preroll: true),
            onSeek: _onVideoSeek,
            totalDurationSeconds: data.info.duration,
            speakerTimeline: data.speakerTimeline,
            speakers: data.summary.summary.speakers,
          ),
        ],
      );
    } else if (isWide) {
      // Desktop narrow: TOC | content (bez video panela)
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: data.article,
            activeTimestamp: _activeTimestamp,
            onSectionTap: (ts) {
              setState(() => _activeTimestamp = ts);
              _seekAndPlay(ts);
            },
          ),
          Expanded(child: scrollBody),
        ],
      );
    } else {
      // Mobitel: samo scroll content, Drawer za TOC
      body = scrollBody;
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      drawer: isWide
          ? null
          : Drawer(
              child: TableOfContents(
                article: data.article,
                activeTimestamp: _activeTimestamp,
                onSectionTap: _drawerTap,
              ),
            ),
      endDrawer: _videoReady && !showVideo
          ? Drawer(
              width: 360,
              child: VideoPanel(
                player: _player!,
                controller: _videoController!,
                chapters: _videoChapters,
                activeTimestamp: _activeTimestamp,
                onChapterTap: (ts) => _seekAndPlay(ts, preroll: true),
                onSeek: _onVideoSeek,
                totalDurationSeconds: data.info.duration,
                speakerTimeline: data.speakerTimeline,
                speakers: data.summary.summary.speakers,
                width: null,
              ),
            )
          : null,
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------

class _MetadataFooter extends StatelessWidget {
  final EpisodeData data;

  const _MetadataFooter({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = data.summary;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Metadata',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _MetaRow('YouTube ID', data.info.id),
          _MetaRow('Kanal', data.info.channel),
          _MetaRow('Model (sažetak)', summary.model),
          _MetaRow('Model (članak)', data.article.metadata.model),
          _MetaRow(
            'Generirano',
            summary.generatedAt.toIso8601String().substring(0, 10),
          ),
          _MetaRow('Jezik', summary.summary.language.toUpperCase()),
          _MetaRow('Tip sadržaja', summary.summary.contentType),
          _MetaRow('Sentiment', summary.summary.sentiment),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
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
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
