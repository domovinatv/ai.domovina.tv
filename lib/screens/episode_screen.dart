import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/background_audio.dart';
import '../services/channel_cache.dart';
import '../services/data_service.dart';
import '../services/cdn_config.dart';
import '../services/notification_art.dart';
import '../services/open_url.dart';
import '../services/view_mode.dart';
import '../widgets/hero_section.dart';
import '../widgets/summary_section.dart';
import '../widgets/chapters_section.dart';
import '../widgets/article_section.dart';
import '../widgets/magisterium_panel.dart';
import '../widgets/magisterium_v2_view.dart';
import '../widgets/entities_section.dart';
import '../widgets/table_of_contents.dart';
import '../widgets/video_panel.dart';

class EpisodeScreen extends StatefulWidget {
  final String youtubeId;

  /// Start at position in seconds (from ?t= query param, like YouTube).
  final int? startAtSeconds;

  const EpisodeScreen({
    super.key,
    required this.youtubeId,
    this.startAtSeconds,
  });

  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  EpisodeData? _data;
  Object? _error;
  final Map<String, (bool done, bool ok)> _assetStatus = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await EpisodeData.loadWithProgress(
        youtubeId: widget.youtubeId,
        onProgress: (asset, done, ok) {
          if (mounted) setState(() => _assetStatus[asset] = (done, ok));
        },
      );
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) {
      return _EpisodeContent(
        data: _data!,
        startAtSeconds: widget.startAtSeconds,
      );
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
                        ? 'Epizoda "${widget.youtubeId}" nije pronađena na CDN-u.\n\nProvjeri je li ID ispravan i jesu li datoteke uploadane.'
                        : 'Greška pri učitavanju podataka:\n$_error',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (notFound)
                    Text(
                      CdnConfig.infoUrl(widget.youtubeId),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
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

    // Loading screen with per-asset progress
    return _LoadingScreen(
      youtubeId: widget.youtubeId,
      assetStatus: _assetStatus,
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  final String youtubeId;
  final Map<String, (bool done, bool ok)> assetStatus;

  const _LoadingScreen({required this.youtubeId, required this.assetStatus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doneCount = assetStatus.values.where((s) => s.$1).length;
    final totalCount = assetStatus.isEmpty ? 7 : assetStatus.length;
    final progress = totalCount > 0 ? doneCount / totalCount : 0.0;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress ring
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    value: assetStatus.isEmpty ? null : progress,
                    strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Ucitavanje epizode',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  youtubeId,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                // Asset status list
                ...assetStatus.entries.map((e) {
                  final (done, ok) = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: done
                              ? Icon(
                                  ok
                                      ? Icons.check_circle
                                      : Icons.remove_circle_outline,
                                  size: 18,
                                  color: ok
                                      ? const Color(0xFF2E7D32)
                                      : theme.colorScheme.onSurfaceVariant
                                            .withAlpha(100),
                                )
                              : const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          e.key,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: done && !ok
                                ? theme.colorScheme.onSurfaceVariant.withAlpha(
                                    100,
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EpisodeContent extends StatefulWidget {
  final EpisodeData data;
  final int? startAtSeconds;

  const _EpisodeContent({required this.data, this.startAtSeconds});

  @override
  State<_EpisodeContent> createState() => _EpisodeContentState();
}

class _EpisodeContentState extends State<_EpisodeContent>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();
  late final Map<String, GlobalKey> _sectionKeys;
  late final Map<String, GlobalKey> _magSectionKeys;
  String? _activeTimestamp; // prati video player poziciju
  String? _scrollTimestamp; // prati scroll poziciju srednje liste

  // Mobile tab switcher: 0 = članak, 1 = Magisterium.
  // Aktivan samo kad je !isWide && hasMag (inače nema tab bara).
  int _mobileTab = 0;

  /// Sprjecava ponavljanje auto-open endDrawera ako korisnik zatvori panel.
  bool _endDrawerAutoOpened = false;

  /// Kad app ode u background dok je endDrawer otvoren, Android unisti
  /// SurfaceView pa media_kit auto-pauzira. Mitigacija: zatvori drawer
  /// na `paused` (Video widget detacha -> audio nastavi) i reopen na
  /// `resumed` da korisnik pri povratku (npr. klik na notifikaciju) vidi
  /// player kakav je bio.
  bool _endDrawerWasOpenBeforeBg = false;

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

  /// Sprjecava auto-sync activeTimestamp iz video position listenera
  /// tijekom rucnog klika na chapter (preroll seek, TOC klik, itd.)
  DateTime? _seekLock;
  static const _seekLockDuration = Duration(milliseconds: 2100);

  /// Web muted autoplay — video igra ali je mutiran, korisnik mora kliknuti za zvuk.
  bool _mutedAutoplay = false;

  /// Kratki lock koji sprjecava scroll listener da overridea scrollTimestamp
  /// dok traje programatski scroll (auto-scroll iz video playbacka).
  DateTime? _scrollLock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _sectionKeys = {
      for (final iter in widget.data.article.iterations)
        for (final sec in iter.sections) sec.screenshotTimestamp: GlobalKey(),
    };

    // Keys za Magisterium stupac — scroll sync (primary variant)
    final magPrimary = widget.data.magisteriumPrimary;
    _magSectionKeys = {
      if (magPrimary != null)
        for (final iter in magPrimary.iterations)
          for (final sec in iter.sections)
            if (sec.magisterium != null) sec.screenshotTimestamp: GlobalKey(),
    };

    _sortedSections = [
      for (final iter in widget.data.article.iterations)
        for (final sec in iter.sections)
          (
            dur: _parseDuration(sec.screenshotTimestamp),
            ts: sec.screenshotTimestamp,
          ),
    ]..sort((a, b) => a.dur.compareTo(b.dur));

    _videoChapters = _sortedSections.map((s) {
      final label = _subtitleForTimestamp(s.ts);
      return VideoChapterMark(position: s.dur, timestamp: s.ts, label: label);
    }).toList();

    _scrollController.addListener(_onScroll);
    _initVideo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _positionSub?.cancel();
    BackgroundAudio.instance.detach();
    _player?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = _scaffoldKey.currentState;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (s?.isEndDrawerOpen == true) {
        _endDrawerWasOpenBeforeBg = true;
        s!.closeEndDrawer();
      }
      // Android kill-a SurfaceView kad Video widget ode u bg pa media_kit
      // auto-pauzira. Force-play kratko nakon tranzicije — foreground service
      // iz audio_service-a drzi process zivim, pa play() prodje.
      // Web: ne force-playamo, browser hendla media sam i user-pauzu treba
      // postivati kad tab ode u pozadinu.
      if (!kIsWeb) {
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          _player?.play();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_endDrawerWasOpenBeforeBg) {
        _endDrawerWasOpenBeforeBg = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scaffoldKey.currentState?.openEndDrawer();
        });
      }
    }
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
    final startAt = widget.startAtSeconds;
    debugPrint(
      'Video: opening $videoUri${startAt != null ? ' @${startAt}s' : ''}',
    );

    try {
      final player = Player();
      final controller = VideoController(player);

      if (kIsWeb) {
        // Web: pokusaj unmuted autoplay (radi ako korisnik ima MEI score
        // za domenu — tj. vec je klikao na stranici). Ako browser odbije,
        // fallback na muted autoplay.
        await player.open(Media(videoUri), play: false);
        if (startAt != null) {
          await player.seek(Duration(seconds: startAt));
        }
        try {
          await player.play();
          // Uspjelo! Browser dopustio unmuted autoplay.
        } catch (_) {
          // Browser odbio — muted autoplay fallback
          await player.setVolume(0);
          await player.play();
          _mutedAutoplay = true;
        }
        // Ako player nije pokrenuo (tihi fail bez exceptiona),
        // provjeri playing state nakon kratke pauze
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!player.state.playing) {
          await player.setVolume(0);
          await player.play();
          _mutedAutoplay = true;
        }
      } else {
        // Native: autoplay radi normalno
        await player.open(Media(videoUri), play: true);
        if (startAt != null) {
          await player.seek(Duration(seconds: startAt));
        }
      }

      _positionSub = player.stream.position.listen(_onVideoPosition);

      if (mounted) {
        setState(() {
          _player = player;
          _videoController = controller;
          _videoReady = true;
        });
        debugPrint('Video: ready');

        // Background audio session — lock screen + notification na native, no-op na webu.
        // Artwork strategija:
        //   iOS: 1:1 channel avatar (savrseno fit u Now Playing square widget).
        //   Android: 2:1 runtime-composed slika (1:1 avatar + 16:9 thumbnail)
        //     jer Android 13+ MediaStyle crop-a u widescreen; kompozicija ispuni
        //     tile elegantno. Fallback na 1:1 avatar ili YouTube thumbnail.
        await channelCache.loadIndex();
        final channelName = widget.data.info.channel;
        final squareUrl = channelCache.avatarSquareForChannelName(channelName);
        final thumbUrl = widget.data.info.thumbnail;
        final composed = squareUrl != null
            ? await NotificationArt.composeForAndroid(
                videoId: widget.data.youtubeId,
                avatarSquareUrl: squareUrl,
                thumbnail16x9Url: thumbUrl,
              )
            : null;
        final summaryTitle = widget.data.summary.summary.titleHr;
        BackgroundAudio.instance.attach(
          player: player,
          title: summaryTitle.isNotEmpty ? summaryTitle : widget.data.info.title,
          artist: channelName,
          artUri: composed ?? squareUrl ?? thumbUrl,
          duration: Duration(seconds: widget.data.info.duration),
        );

        // Postavi inicijalni chapter za startAt
        if (startAt != null) {
          _setInitialChapter(Duration(seconds: startAt));
        }

        // Native mobile (Android/iOS): auto-open video endDrawer cim video postane spreman,
        // jer je autoplay pa korisnik odmah zeli vidjeti playback. Web je izuzet (autoplay
        // policy moze biti mutirana). Desktop ima inline video panel, ne endDrawer.
        if (!kIsWeb && !_endDrawerAutoOpened) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final width = MediaQuery.sizeOf(context).width;
            // EndDrawer je renderiran samo kad width <= 1100 (tada !showVideo).
            if (width <= 1100) {
              _scaffoldKey.currentState?.openEndDrawer();
              _endDrawerAutoOpened = true;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Video: init failed — $e');
    }
  }

  /// Postavi activeTimestamp + scrollTimestamp za inicijalnu poziciju.
  void _setInitialChapter(Duration pos) {
    String? ts;
    for (final s in _sortedSections) {
      if (pos >= s.dur) {
        ts = s.ts;
      } else {
        break;
      }
    }
    if (ts != null) {
      setState(() {
        _activeTimestamp = ts;
        _scrollTimestamp = ts;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToSection(ts!);
      });
    }
  }

  void _onVideoPosition(Duration pos) {
    // Preskoči auto-sync tijekom rucnog klika na chapter
    final lock = _seekLock;
    final now = DateTime.now();
    if (lock != null && now.difference(lock) < _seekLockDuration) {
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

    // Sprjecava flicker: odmah nakon seekLocka, ne dopusti backward jump
    // na raniji chapter (preroll -2s uzrokuje kratki period na prethodnom).
    if (lock != null &&
        now.difference(lock) <
            _seekLockDuration + const Duration(milliseconds: 500)) {
      final currentIdx = _sortedSections.indexWhere(
        (s) => s.ts == _activeTimestamp,
      );
      final newIdx = _sortedSections.indexWhere((s) => s.ts == newTs);
      if (newIdx < currentIdx) return; // ignoriraj backward jump
    }

    // Postavi oba timestampa — video i scroll pointer syncani
    setState(() {
      _activeTimestamp = newTs!;
      _scrollTimestamp = newTs;
    });

    // Auto-scroll teksta samo ako korisnik nije ručno scrollao zadnje 2 sekunde
    final lastScroll = _lastManualScroll;
    if (lastScroll == null ||
        DateTime.now().difference(lastScroll) > const Duration(seconds: 2)) {
      _scrollLock = DateTime.now();
      _scrollToSection(newTs);
    }
  }

  // ---------- scroll --------------------------------------------------------

  void _onScroll() {
    final now = DateTime.now();
    // Ne reagiraj na programatski scroll (seek ili auto-scroll iz playbacka)
    final sLock = _seekLock;
    if (sLock != null && now.difference(sLock) < _seekLockDuration) return;
    final scLock = _scrollLock;
    if (scLock != null &&
        now.difference(scLock) < const Duration(milliseconds: 300))
      return;
    _lastManualScroll = now;
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
        if (_scrollTimestamp != entry.key) {
          setState(() => _scrollTimestamp = entry.key);
        }
        return;
      }
    }
  }

  // Alignment offset — appbar je ~56px, na tipicnom viewportu (800px) to je ~0.08.
  // Scrollamo ispod headera da chapter naslov bude jasno vidljiv.
  static const _scrollAlignment = 0.18;

  void _scrollToSection(String timestamp) {
    final key = _sectionKeys[timestamp];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: Duration.zero,
        alignment: _scrollAlignment,
      );
    }
    _scrollMagToSection(timestamp);
  }

  void _scrollMagToSection(String timestamp) {
    final key = _magSectionKeys[timestamp];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: Duration.zero,
        alignment: _scrollAlignment,
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
    _seekLock = DateTime.now();
    // Odmah postavi oba pointera i scrollaj — ne cekaj async seek
    setState(() {
      _activeTimestamp = timestamp;
      _scrollTimestamp = timestamp;
    });
    _scrollToSection(timestamp);

    final dur = _parseDuration(timestamp);
    var seekTo = dur;
    if (preroll) {
      seekTo = dur - const Duration(seconds: 2);
      if (seekTo < Duration.zero) seekTo = Duration.zero;
    }
    if (kIsWeb) {
      await _player?.play();
      await _player?.seek(seekTo);
    } else {
      await _player?.seek(seekTo);
      await _player?.play();
    }
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
    final magVariants = data.magisteriumVariants;
    final magV2 = data.magisteriumFullV2;
    final hasMag =
        magVariants.isNotEmpty ||
        data.magisteriumFull != null ||
        data.magisteriumFullPrompt != null ||
        magV2 != null;
    // Magisterium stupac: zasebni scrollable panel na širokim ekranima
    final showMagColumn = hasMag && width > 1500;
    // Mobile: bottom tabovi za switch između článka i Magisteriuma.
    // Bez ovog, Magisterium content je "zakopan" ispod dugačke article liste.
    final showMobileBottomBar = !isWide;
    final isMobileWithTabs = !isWide && hasMag;

    final scrollBody = CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverAppBar(
          pinned: true,
          leading: isWide
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Natrag',
                  onPressed: () => context.go('/'),
                ),
          automaticallyImplyLeading: false,
          title: Text(
            data.info.channel,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
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
            IconButton(
              icon: const Icon(Icons.smart_display, color: Color(0xFFFF0000)),
              tooltip: 'Otvori na YouTube',
              onPressed: () =>
                  openUrl('https://www.youtube.com/watch?v=${data.youtubeId}'),
            ),
            IconButton(
              icon: const Icon(Icons.unfold_less),
              tooltip: 'Jednostavni prikaz',
              onPressed: () async {
                await saveSimpleModePref(true);
                if (!context.mounted) return;
                context.go('/m/${data.youtubeId}');
              },
            ),
            if (_videoReady && !showVideo)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: const Icon(Icons.ondemand_video),
                  tooltip: 'Video',
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
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
                  HeroSection(info: data.info, youtubeId: data.youtubeId),
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
                    onPlayTap: _videoReady
                        ? (ts) => _seekAndPlay(ts, preroll: true)
                        : null,
                    magisterium: data.magisteriumPrimary,
                  ),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  // Magisterium inline: samo kad NIJE prikazan kao stupac
                  // i kad nismo u mobile-tab modu (tamo ima svoj zasebni tab).
                  if (hasMag && !showMagColumn && !isMobileWithTabs) ...[
                    if (magV2 != null)
                      MagisteriumV2View(data: magV2)
                    else
                      MagisteriumPanel(
                        variants: magVariants,
                        magisteriumFull: data.magisteriumFull,
                        magisteriumFullPrompt: data.magisteriumFullPrompt,
                      ),
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                    const SizedBox(height: 12),
                  ],
                  EntitiesSection(summary: data.summary.summary),
                  _MetadataFooter(data: data),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    // Mobile Magisterium tab — zasebni scroll view s istim SliverAppBar patternom
    Widget? mobileMagScroll;
    if (isMobileWithTabs) {
      mobileMagScroll = CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Natrag',
              onPressed: () => context.go('/'),
            ),
            automaticallyImplyLeading: false,
            title: Text(
              data.info.channel,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
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
              IconButton(
                icon: const Icon(Icons.unfold_less),
                tooltip: 'Jednostavni prikaz',
                onPressed: () async {
                  await saveSimpleModePref(true);
                  if (!context.mounted) return;
                  context.go('/m/${data.youtubeId}');
                },
              ),
              if (_videoReady)
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
                // Preferiraj v2 view ako postoji (noviji format), inace stari Panel.
                child: magV2 != null
                    ? MagisteriumV2View(
                        data: magV2,
                        padding: const EdgeInsets.all(16),
                      )
                    : MagisteriumPanel(
                        variants: magVariants,
                        magisteriumFull: data.magisteriumFull,
                        magisteriumFullPrompt: data.magisteriumFullPrompt,
                      ),
              ),
            ),
          ),
        ],
      );
    }

    // Magisterium stupac — neovisno scrollable, blog-post stil
    Widget? magColumn;
    if (showMagColumn) {
      // V2 view nema fillParent/sectionKeys — wrappamo u SingleChildScrollView
      // da bi stupac imao vlastiti scroll, isto kao stari Panel s fillParent.
      final inner = magV2 != null
          ? SingleChildScrollView(
              child: MagisteriumV2View(
                data: magV2,
                padding: const EdgeInsets.all(20),
              ),
            )
          : MagisteriumPanel(
              variants: magVariants,
              magisteriumFull: data.magisteriumFull,
              magisteriumFullPrompt: data.magisteriumFullPrompt,
              fillParent: true,
              sectionKeys: _magSectionKeys,
            );
      magColumn = Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
        ),
        child: inner,
      );
    }

    Widget body;
    if (showVideo && showMagColumn) {
      // Ultrawide: TOC | content | magisterium | video
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: data.article,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onSectionTap: _seekAndPlay,
          ),
          Expanded(flex: 3, child: scrollBody),
          Expanded(flex: 2, child: magColumn!),
          VideoPanel(
            player: _player!,
            controller: _videoController!,
            chapters: _videoChapters,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onChapterTap: _seekAndPlay,
            onSeek: _onVideoSeek,
            totalDurationSeconds: data.info.duration,
            speakerTimeline: data.speakerTimeline,
            speakers: data.summary.summary.speakers,
            mutedAutoplay: _mutedAutoplay,
            onUnmute: () => setState(() => _mutedAutoplay = false),
          ),
        ],
      );
    } else if (showMagColumn) {
      // Wide bez videa: TOC | content | magisterium
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
          Expanded(flex: 3, child: scrollBody),
          Expanded(flex: 2, child: magColumn!),
        ],
      );
    } else if (showVideo) {
      // Desktop wide: TOC | content | video
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: data.article,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onSectionTap: _seekAndPlay,
          ),
          Expanded(child: scrollBody),
          VideoPanel(
            player: _player!,
            controller: _videoController!,
            chapters: _videoChapters,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onChapterTap: _seekAndPlay,
            onSeek: _onVideoSeek,
            totalDurationSeconds: data.info.duration,
            speakerTimeline: data.speakerTimeline,
            speakers: data.summary.summary.speakers,
            mutedAutoplay: _mutedAutoplay,
            onUnmute: () => setState(() => _mutedAutoplay = false),
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
    } else if (isMobileWithTabs) {
      // Mobitel s Magisteriumom: IndexedStack — članak (tab 0) ili Magisterium (tab 1)
      body = IndexedStack(
        index: _mobileTab,
        children: [scrollBody, mobileMagScroll!],
      );
    } else {
      // Mobitel bez Magisteriuma: samo scroll content, Drawer za TOC
      body = scrollBody;
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      drawer: isWide
          ? null
          : Drawer(
              child: SafeArea(
                child: TableOfContents(
                  article: data.article,
                  activeTimestamp: _activeTimestamp,
                  scrollTimestamp: _scrollTimestamp,
                  onSectionTap: _drawerTap,
                ),
              ),
            ),
      endDrawer: _videoReady && !showVideo
          ? Drawer(
              width: 360,
              child: SafeArea(
                child: VideoPanel(
                  player: _player!,
                  controller: _videoController!,
                  chapters: _videoChapters,
                  activeTimestamp: _activeTimestamp,
                  onChapterTap: _seekAndPlay,
                  onSeek: _onVideoSeek,
                  totalDurationSeconds: data.info.duration,
                  speakerTimeline: data.speakerTimeline,
                  speakers: data.summary.summary.speakers,
                  width: null,
                ),
              ),
            )
          : null,
      // SliverAppBar (primary: true) respektira top safe area, pa top: false.
      // Bottom: true samo kad nema bottomNavigationBara (inace bi stvorilo gap).
      body: SafeArea(
        top: false,
        bottom: !showMobileBottomBar,
        child: body,
      ),
      bottomNavigationBar: showMobileBottomBar
          ? Material(
              color: theme.colorScheme.surface,
              elevation: 3,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      _BottomBarButton(
                        icon: Icons.menu,
                        label: 'Sadržaj',
                        isActive: false,
                        onTap: () {
                          final s = _scaffoldKey.currentState;
                          if (s == null) return;
                          if (s.isDrawerOpen) {
                            s.closeDrawer();
                          } else {
                            s.openDrawer();
                          }
                        },
                      ),
                      if (isMobileWithTabs) ...[
                        _BottomBarButton(
                          icon: _mobileTab == 0
                              ? Icons.article
                              : Icons.article_outlined,
                          label: 'Članak',
                          isActive: _mobileTab == 0,
                          onTap: () => setState(() => _mobileTab = 0),
                        ),
                        _BottomBarButton(
                          icon: _mobileTab == 1
                              ? Icons.menu_book
                              : Icons.menu_book_outlined,
                          label: 'Magisterium',
                          isActive: _mobileTab == 1,
                          onTap: () => setState(() => _mobileTab = 1),
                        ),
                      ],
                      _BottomBarButton(
                        icon: Icons.ondemand_video,
                        label: 'Video',
                        isActive: false,
                        onTap: _videoReady
                            ? () {
                                final s = _scaffoldKey.currentState;
                                if (s == null) return;
                                if (s.isEndDrawerOpen) {
                                  s.closeEndDrawer();
                                } else {
                                  s.openEndDrawer();
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
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
          if (data.magisteriumPrimary != null)
            _MetaRow('Model (teologija)', data.magisteriumPrimary!.model),
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

class _BottomBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _BottomBarButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    if (onTap == null) {
      color = theme.colorScheme.onSurfaceVariant.withAlpha(80);
    } else if (isActive) {
      color = theme.colorScheme.primary;
    } else {
      color = theme.colorScheme.onSurfaceVariant;
    }

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
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
