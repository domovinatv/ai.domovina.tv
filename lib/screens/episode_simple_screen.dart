import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/app_localizations.dart';
import '../models/person_hub.dart';
import '../pinka_sdk/pinka_sdk.dart';
import '../onboarding/moments/m1_save_progress_toast.dart';
import '../onboarding/moments/m2_link_identity_sheet.dart';
import '../onboarding/triggers/watch_seconds_tracker.dart';
import '../services/background_audio.dart';
import '../services/cdn_config.dart';
import '../services/channel_cache.dart';
import '../services/data_service.dart';
import '../services/episode_language.dart';
import '../services/notification_art.dart';
import '../services/open_url.dart';
import '../services/player_resume.dart';
import '../services/url_sync.dart';
import '../services/view_mode.dart';
import '../services/watch_progress_service.dart';
import '../widgets/audio_poster.dart';
import '../widgets/clip_share_sheet.dart';
import '../widgets/episode_video.dart';
import '../widgets/favorite_button.dart';
import '../widgets/language_toggle_chip.dart';
import '../widgets/magisterium_v2_view.dart';
import '../widgets/resume_hint_banner.dart';
import '../widgets/speaker_chip.dart';
import '../widgets/view_mode_toggle_button.dart';
import '../widgets/youtube_embed.dart';

/// Pojednostavljeni mobile-first ekran za reprodukciju podcast epizode.
/// Optimiziran za slušanje u autu — 3 taba: Player, Poglavlja, Info.
class EpisodeSimpleScreen extends StatefulWidget {
  final String youtubeId;

  /// True kad URL ima `/en` sufix (npr. `/m/<id>/en`).
  final bool initialLanguageEn;

  /// Eksplicitni start timestamp iz URL-a (`/m/<id>/t/<sec>`). Ima prednost
  /// nad saved watch progress-om. null → resume na zadnju poziciju.
  final int? startAtSeconds;

  const EpisodeSimpleScreen({
    super.key,
    required this.youtubeId,
    this.initialLanguageEn = false,
    this.startAtSeconds,
  });

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
      return _SimpleEpisodeContent(
        data: _data!,
        initialLanguageEn: widget.initialLanguageEn,
        startAtSeconds: widget.startAtSeconds,
      );
    }

    if (_error != null) {
      final notFound = _error is VideoNotFoundException;
      final theme = Theme.of(context);
      final l = AppLocalizations.of(context);
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
                        ? l.episodeNotFound(widget.youtubeId)
                        : l.episodeLoadError('$_error'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(l.commonBack),
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
  final bool initialLanguageEn;
  final int? startAtSeconds;

  const _SimpleEpisodeContent({
    required this.data,
    this.initialLanguageEn = false,
    this.startAtSeconds,
  });

  @override
  State<_SimpleEpisodeContent> createState() => _SimpleEpisodeContentState();
}

class _SimpleEpisodeContentState extends State<_SimpleEpisodeContent>
    with WidgetsBindingObserver {
  int _tabIndex = 0;
  EpisodeLanguage _language = EpisodeLanguage.hr;

  // Video
  Player? _player;
  VideoController? _videoController;
  bool _videoReady = false;
  StreamSubscription<Duration>? _positionSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  /// In-app YouTube embed mode — native player pauziran, iframe preuzima.
  bool _ytMode = false;

  /// Cover-art za audio-only epizode (CORS-safe channel avatar square).
  /// Razrješava se u [_initVideo] iz channel cachea.
  String? _audioArtUrl;

  /// URL sync — zadnja sekunda za koju smo update-ali address bar.
  int _lastUrlSyncedSec = -1;

  /// Inline resume hint — vidi episode_screen.dart za razlog (SnackBar lingera).
  int? _resumeHintSeconds;
  Timer? _resumeHintTimer;
  static const _resumeHintDuration = Duration(seconds: 4);

  /// Flat lista svih poglavlja iz outline-a za brz pristup.
  late final List<({String timestamp, String topic, int totalSeconds})>
  _chapters;

  late final WatchSecondsTracker _watchTracker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chapters = _buildChapters();
    _watchTracker = WatchSecondsTracker(
      triggerAt: 30,
      onThreshold: () {
        if (mounted) maybeShowM2(context);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowM1(context);
    });

    if (widget.initialLanguageEn && widget.data.hasTranslationEn) {
      _language = EpisodeLanguage.en;
    } else {
      loadPreferredLanguage().then((saved) {
        if (!mounted) return;
        if (saved == EpisodeLanguage.en && widget.data.hasTranslationEn) {
          setState(() => _language = EpisodeLanguage.en);
          _syncLanguageUrl(EpisodeLanguage.en);
        }
      });
    }
    _initVideo();
  }

  void _onLanguageChanged(EpisodeLanguage lang) {
    if (lang == _language) return;
    setState(() => _language = lang);
    savePreferredLanguage(lang);
    _syncLanguageUrl(lang);
  }

  void _syncLanguageUrl(EpisodeLanguage lang) {
    final sec = _position.inSeconds;
    replaceLanguage(
      '/m/${widget.data.youtubeId}',
      isEn: lang == EpisodeLanguage.en,
      seconds: sec,
    );
    _lastUrlSyncedSec = sec;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _resumeHintTimer?.cancel();
    _watchTracker.dispose();
    WatchProgressService.instance.flush();
    BackgroundAudio.instance.detach();
    _player?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android kill-a SurfaceView kad Video widget (u _PlayerTab) ode u bg
    // pa media_kit auto-pauzira. Force-play kratko nakon tranzicije —
    // foreground service iz audio_service-a drzi process zivim.
    // Web: ne force-playamo — browser hendla media sam, a force-play bi
    // poništio rucnu Pause kad korisnik prebaci tab.
    if (kIsWeb) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        _player?.play();
      });
    }
  }

  List<({String timestamp, String topic, int totalSeconds})> _buildChapters() {
    final outline = widget.data.outline;
    if (outline == null) return const [];
    final list = <({String timestamp, String topic, int totalSeconds})>[];
    for (final iter in outline.iterations) {
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
    // Nema playabilne medije (sva 3 probe-a 404) — ne otvaraj player; _PlayerTab
    // prikazuje jasnu poruku umjesto beskonačnog spinnera.
    if (!widget.data.hasMedia || widget.data.videoUri.isEmpty) {
      return;
    }
    // URL explicit timestamp (`/m/<id>/t/<sec>`) ima prednost nad saved
    // progress-om. Inače resume na zadnju poziciju ako > 5s i nije completed
    // (rewatch konvencija — kreni od početka).
    int? startAt = widget.startAtSeconds;
    bool resumedFromSaved = false;
    if (startAt == null) {
      final saved = WatchProgressService.instance.getSync(
        widget.data.youtubeId,
      );
      if (saved != null && !saved.completed && saved.positionSeconds > 5) {
        startAt = saved.positionSeconds;
        resumedFromSaved = true;
      }
    }

    try {
      final player = Player();
      final controller = VideoController(player);

      // VAZNO: subscribe-i moraju biti registrirani PRIJE open/play.
      // media_kit streamovi su broadcast (ne replay) — ako se prvi
      // playing=true event ispali prije nego sto smo se pretplatili (npr.
      // pri brzoj internoj navigaciji s vec keshanim Player resursima),
      // izgubimo event i Play/Pause gumb ostaje u krivom stanju.
      _positionSub = player.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
        // URL sync: adresna traka prati player na 1Hz (sec granularity).
        // Stream fira ~5×/s — preskačemo update kad se sec nije promijenio.
        final sec = pos.inSeconds;
        if (sec != _lastUrlSyncedSec) {
          _lastUrlSyncedSec = sec;
          replaceTimestamp(
            '/m/${widget.data.youtubeId}',
            sec,
            langSuffix: _language == EpisodeLanguage.en ? '/en' : null,
          );
          // CDN URL (ne i.ytimg.com) da home rail "Nastavi slusati" moze
          // renderati thumbnail bez CORS bloka.
          WatchProgressService.instance.scheduleSave(
            episodeId: widget.data.youtubeId,
            positionSeconds: sec,
            durationSeconds: widget.data.info.duration,
            channelId: widget.data.info.channelId,
            episodeTitle: widget.data.displayTitle,
            episodeThumbnailUrl: CdnConfig.thumbnailUrl(widget.data.youtubeId),
          );
        }
      });

      player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
        if (playing) {
          _watchTracker.start();
        } else {
          _watchTracker.pause();
        }
      });

      // Otvori + pouzdano resume-seek (čeka duration prije seeka — inače libmpv
      // na iOS odbaci seek pa video kreće od 0). Web fallback na muted autoplay
      // je u helperu.
      await openAndResume(
        player,
        uri: widget.data.videoUri,
        startAtSeconds: startAt,
      );

      if (mounted) {
        setState(() {
          _player = player;
          _videoController = controller;
          _videoReady = true;
          // Safety snapshot — ako je playing event procurio kroz timing
          // gap (rijetko, ali moguce), sinkroniziraj iz player.state.
          _isPlaying = player.state.playing;
          _position = player.state.position;
          _duration = player.state.duration;
        });

        if (resumedFromSaved && startAt != null) {
          _showResumeHint(startAt);
        }

        // Background audio session — vidi episode_screen.dart za strategiju artworka.
        await channelCache.loadIndex();
        final channelName = widget.data.info.channel;
        final squareUrl = channelCache.avatarSquareForChannelName(channelName);
        if (mounted && squareUrl != null) {
          setState(() => _audioArtUrl = squareUrl);
        }
        final thumbUrl = widget.data.info.thumbnail;
        final composed = squareUrl != null
            ? await NotificationArt.composeForAndroid(
                videoId: widget.data.youtubeId,
                avatarSquareUrl: squareUrl,
                thumbnail16x9Url: thumbUrl,
              )
            : null;
        BackgroundAudio.instance.attach(
          player: player,
          title: widget.data.displayTitle,
          artist: channelName,
          artUri: composed ?? squareUrl ?? thumbUrl,
          duration: Duration(seconds: widget.data.info.duration),
        );
      }
    } catch (e) {
      debugPrint('SimpleEpisode: video init failed — $e');
    }
  }

  void _showResumeHint(int positionSeconds) {
    if (!mounted) return;
    _resumeHintTimer?.cancel();
    setState(() => _resumeHintSeconds = positionSeconds);
    _resumeHintTimer = Timer(_resumeHintDuration, () {
      if (mounted) setState(() => _resumeHintSeconds = null);
    });
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

  /// Kopira share link na trenutnu poziciju playera (path-based `/v/<id>/t/<sec>`).
  /// Vidi web/_worker.js — chapter-aware OG injection na ovaj path.
  void _copyMomentLink(BuildContext context, String youtubeId) {
    final pos = _player?.state.position ?? Duration.zero;
    final sec = pos.inSeconds;
    final url = sec > 5
        ? 'https://domovina.ai/v/$youtubeId/t/$sec'
        : 'https://domovina.ai/v/$youtubeId';
    Clipboard.setData(ClipboardData(text: url));
    String label;
    if (sec > 5) {
      final h = sec ~/ 3600;
      final m = (sec % 3600) ~/ 60;
      final s = sec % 60;
      String p(int n) => n.toString().padLeft(2, '0');
      label = h > 0 ? '$h:${p(m)}:${p(s)}' : '$m:${p(s)}';
    } else {
      label = AppLocalizations.of(context).episodeWholeEpisode;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).episodeLinkCopied(label)),
        duration: const Duration(seconds: 2),
      ),
    );
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
    final l = AppLocalizations.of(context);
    final data = widget.data;
    final wantEn = _language == EpisodeLanguage.en;
    final magV2 = data.magisteriumFullV2For(wantEn: wantEn);

    // Dinamicke tabove — Magisterium tab se prikazuje samo ako postoji v2 JSON.
    final tabs = <Widget>[
      _PlayerTab(
        data: data,
        player: _player,
        videoController: _videoController,
        videoReady: _videoReady,
        position: _position,
        duration: _duration,
        isPlaying: _isPlaying,
        ytMode: _ytMode,
        audioOnly: data.isAudioOnly,
        hasMedia: data.hasMedia,
        posterUrl: _audioArtUrl,
        onEnterYtMode: () {
          _player?.pause();
          setState(() => _ytMode = true);
        },
        onExitYtMode: () => setState(() => _ytMode = false),
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
        videoId: widget.data.isAudioOnly ? null : widget.data.youtubeId,
        episodeDurationSec: widget.data.info.duration,
      ),
      if (magV2 != null)
        SingleChildScrollView(child: MagisteriumV2View(data: magV2)),
      _InfoTab(data: data),
    ];

    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.play_circle_outline),
        selectedIcon: const Icon(Icons.play_circle_filled),
        label: l.episodeTabPlayer,
      ),
      NavigationDestination(
        icon: const Icon(Icons.list_outlined),
        selectedIcon: const Icon(Icons.list),
        label: l.episodeTabChapters,
      ),
      if (magV2 != null)
        const NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: 'Magisterium',
        ),
      NavigationDestination(
        icon: const Icon(Icons.info_outline),
        selectedIcon: const Icon(Icons.info),
        label: l.episodeTabInfo,
      ),
    ];

    // Clamp selected index ako se broj tabova promjeni (npr. v2 loada nakon rebuilda).
    final safeIndex = _tabIndex.clamp(0, tabs.length - 1);

    return EpisodeLanguageScope(
      language: _language,
      hasTranslationEn: data.hasTranslationEn,
      child: Scaffold(
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
            FavoriteButton(episodeId: data.youtubeId),
            if (data.hasTranslationEn)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(
                  child: LanguageToggleChip(
                    current: _language,
                    onChanged: _onLanguageChanged,
                    compact: true,
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: l.episodeCopyMomentLink,
              onPressed: () => _copyMomentLink(context, data.youtubeId),
            ),
            if (data.info.sourceUrl != null)
              IconButton(
                icon: data.isAudioOnly
                    ? const Icon(Icons.open_in_new)
                    : const Icon(Icons.smart_display, color: Color(0xFFFF0000)),
                tooltip: data.isAudioOnly
                    ? l.commonOpenSource
                    : l.episodeOpenOnYouTube,
                onPressed: () => openUrl(data.info.sourceUrl!),
              ),
            ViewModeToggleButton(
              toSimple: false,
              onPressed: () async {
                await saveSimpleModePref(false);
                if (!context.mounted) return;
                final target = _language == EpisodeLanguage.en
                    ? '/v/${data.youtubeId}/en'
                    : '/v/${data.youtubeId}';
                context.go(target);
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                // Responzivnost: koliko tabova stane side-by-side?
                // ~440px je minimum prije nego sadrzaj (video 16:9, lista poglavlja,
                // markdown clanak) postane previse skucen.
                const minPanelWidth = 440.0;
                final visibleCount = (constraints.maxWidth / minPanelWidth)
                    .floor()
                    .clamp(1, tabs.length);
                return _ResponsiveTabLayout(
                  tabs: tabs,
                  destinations: destinations,
                  selectedIndex: safeIndex,
                  visibleCount: visibleCount,
                  onSelect: (i) => setState(() => _tabIndex = i),
                  theme: theme,
                );
              },
            ),
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.2),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _resumeHintSeconds == null
                        ? const SizedBox.shrink()
                        : ResumeHintBanner(
                            key: ValueKey(_resumeHintSeconds),
                            seconds: _resumeHintSeconds!,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Responsive layout — switcha izmedju single-tab+bottom-nav (mobile portrait)
// i multi-column rasporeda (desktop landscape) ovisno o dostupnoj sirini.
//
// visibleCount == 1: jedan tab + bottom nav s svim destinacijama, max-width 720
// visibleCount == tabs.length: Row sa svim tabovima side-by-side, bez bottom nava
// inace: pinanih (visibleCount - 1) tabova s lijeva, zadnji slot je preklopni
//        preko bottom nava (samo preostali tabovi su u nav-u)
// ---------------------------------------------------------------------------

class _ResponsiveTabLayout extends StatelessWidget {
  final List<Widget> tabs;
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final int visibleCount;
  final ValueChanged<int> onSelect;
  final ThemeData theme;

  const _ResponsiveTabLayout({
    required this.tabs,
    required this.destinations,
    required this.selectedIndex,
    required this.visibleCount,
    required this.onSelect,
    required this.theme,
  });

  Widget _columnDivider() => VerticalDivider(
    width: 1,
    thickness: 1,
    color: theme.colorScheme.outlineVariant.withAlpha(80),
  );

  Widget _navBar({
    required int idx,
    required ValueChanged<int> onTap,
    required List<NavigationDestination> dests,
  }) {
    return NavigationBar(
      selectedIndex: idx,
      onDestinationSelected: onTap,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: dests,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (visibleCount == 1) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: IndexedStack(index: selectedIndex, children: tabs),
              ),
            ),
          ),
          _navBar(idx: selectedIndex, onTap: onSelect, dests: destinations),
        ],
      );
    }

    if (visibleCount >= tabs.length) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < tabs.length; i++) ...[
            if (i > 0) _columnDivider(),
            Expanded(child: tabs[i]),
          ],
        ],
      );
    }

    final pinnedCount = visibleCount - 1;
    final swapStart = pinnedCount;
    final swapTabs = tabs.sublist(swapStart);
    final swapDestinations = destinations.sublist(swapStart);
    final swapIndex = (selectedIndex - swapStart).clamp(0, swapTabs.length - 1);

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < pinnedCount; i++) ...[
                if (i > 0) _columnDivider(),
                Expanded(child: tabs[i]),
              ],
              _columnDivider(),
              Expanded(
                child: IndexedStack(index: swapIndex, children: swapTabs),
              ),
            ],
          ),
        ),
        _navBar(
          idx: swapIndex,
          onTap: (i) => onSelect(swapStart + i),
          dests: swapDestinations,
        ),
      ],
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
  final bool ytMode;
  final bool audioOnly;
  final bool hasMedia;
  final String? posterUrl;
  final VoidCallback onEnterYtMode;
  final VoidCallback onExitYtMode;
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
    required this.ytMode,
    required this.audioOnly,
    required this.hasMedia,
    required this.posterUrl,
    required this.onEnterYtMode,
    required this.onExitYtMode,
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
    final l = AppLocalizations.of(context);
    final info = data.info;
    final lang = EpisodeLanguageScope.of(context);
    final summaryHr = data.summary?.summary;
    final summary = lang == EpisodeLanguage.en
        ? (data.summaryEn?.summary ?? summaryHr)
        : summaryHr;
    // Lokalizirani naslov: prefer EN summary.titleEn → HR summary.titleHr → YouTube original.
    String displayTitle = data.displayTitle;
    if (lang == EpisodeLanguage.en && summary != null) {
      final en = summary.titleEn;
      if (en != null && en.isNotEmpty) displayTitle = en;
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video player (native ili YouTube embed), audio cover-art or thumbnail
          AspectRatio(
            aspectRatio: 16 / 9,
            child: audioOnly
                ? AudioPoster(artUrl: posterUrl)
                : ytMode
                ? YouTubeEmbed(
                    videoId: data.youtubeId,
                    startSeconds: position.inSeconds,
                  )
                : videoReady && videoController != null && player != null
                ? EpisodeVideo(
                    player: player!,
                    controller: videoController!,
                    speakerTimeline: data.speakerTimeline,
                    speakers: summary?.speakers ?? const [],
                    onYouTubeMode: youTubeEmbedSupported ? onEnterYtMode : null,
                  )
                : !hasMedia
                ? ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.music_off,
                            color: Colors.white54,
                            size: 40,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l.episodeMediaUnavailable,
                            style: const TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
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

          if (ytMode) YouTubeModeBar(onExit: onExitYtMode),

          // Seek bar
          if (videoReady && !ytMode) ...[
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: theme.colorScheme.primary,
                inactiveTrackColor: theme.colorScheme.primary.withAlpha(40),
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
                onChanged: (v) => onSeek(Duration(milliseconds: v.toInt())),
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
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    iconSize: 40,
                    onPressed: onPlayPause,
                  ),
                  const SizedBox(width: 8),
                  // Forward 30s
                  IconButton(
                    icon: const Icon(Icons.forward_30),
                    iconSize: 32,
                    onPressed: () =>
                        onSeek(Duration(seconds: position.inSeconds + 30)),
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
                  displayTitle,
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
                if (summary != null && summary.speakers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: summary.speakers
                        .map((s) => SpeakerChip(speaker: s))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 8),
          // "Zid podrške" za epizodu — sam se sakrije ako epizoda nema aktivnu
          // pinka kampanju. SEPA QR + on-chain EURe (Gnosis Safe) + in-app wallet.
          PinkaSupportCard.episode(
            youtubeId: data.youtubeId,
            onOpen: (_) => context.push(
              Uri(
                path: '/v/${data.youtubeId}/support',
                queryParameters: {'name': data.displayTitle},
              ).toString(),
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

  /// Non-null → each chapter row gets a download/share clip action. Null for
  /// audio-only episodes (the cutter needs `video_h264.mp4`).
  final String? videoId;
  final int episodeDurationSec;

  const _ChaptersTab({
    required this.chapters,
    required this.activeIndex,
    required this.onChapterTap,
    this.videoId,
    this.episodeDurationSec = 0,
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
    final l = AppLocalizations.of(context);

    if (chapters.isEmpty) {
      return Center(
        child: Text(
          l.episodeNoChapters,
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
          trailing: () {
            // Clip window: this chapter's start → next chapter's start, or the
            // episode end for the last chapter.
            final startSec = ch.totalSeconds;
            final endSec = i + 1 < chapters.length
                ? chapters[i + 1].totalSeconds
                : episodeDurationSec;
            final chevron = Icon(
              isActive ? Icons.play_arrow : Icons.chevron_right,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              size: 20,
            );
            if (videoId == null || endSec <= startSec) return chevron;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipShareButton(
                  videoId: videoId!,
                  startSec: startSec,
                  endSec: endSec,
                  title: ch.topic,
                ),
                chevron,
              ],
            );
          }(),
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
    final l = AppLocalizations.of(context);
    final info = data.info;
    final lang = EpisodeLanguageScope.of(context);
    final isEn = lang == EpisodeLanguage.en;
    final summaryHr = data.summary?.summary;
    final summary = isEn ? (data.summaryEn?.summary ?? summaryHr) : summaryHr;
    String displayTitle = data.displayTitle;
    if (isEn && summary != null) {
      final en = summary.titleEn;
      if (en != null && en.isNotEmpty) displayTitle = en;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Title
        Text(
          displayTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Pending pipeline banner — only when AI nije gotov.
        if (summary == null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withAlpha(140),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.tertiary.withAlpha(80),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.episodeAiPendingInfo,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Abstract
        if (summary != null) ...[
          Builder(
            builder: (_) {
              final abstractText = pickLang(
                lang,
                summary.abstractHr,
                summary.abstractEn,
              );
              if (abstractText.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(120),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      abstractText,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ],

        // Key topics
        if (summary != null) ...[
          Builder(
            builder: (_) {
              final topics = pickLangList(
                lang,
                summary.keyTopics,
                summary.keyTopicsEn,
              );
              if (topics.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(icon: Icons.topic, label: l.episodeKeyTopics),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: topics.map((t) {
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
              );
            },
          ),
        ],

        // Key points
        if (summary != null && summary.keyPoints.isNotEmpty) ...[
          _SectionTitle(
            icon: Icons.format_list_bulleted,
            label: l.episodeKeyTakeaways,
          ),
          const SizedBox(height: 8),
          ...pickLangList(lang, summary.keyPoints, summary.keyPointsEn).map(
            (kp) => Padding(
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
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Speakers
        if (summary != null && summary.speakers.isNotEmpty) ...[
          _SectionTitle(icon: Icons.people, label: l.episodeSpeakers),
          const SizedBox(height: 8),
          ...summary.speakers.map((s) {
            final roleLabel = isEn ? s.roleLabelEn() : s.roleLabel;
            final name = s.displayName;
            final row = Row(
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
                        // Ako pipeline nije izvukao pravo ime (host se ne
                        // predstavlja), suggested_name je == role — tada
                        // prikazi samo capitalized roleLabel.
                        name ?? roleLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (name != null && s.role.isNotEmpty)
                        Text(
                          roleLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
            // Govornik s pravim imenom → tap na profil (/p/:slug). Anonimni
            // role-labeli nisu u bazi pa se ne linkaju.
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: name == null
                  ? row
                  : InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => context.go('/p/${personSlug(name)}'),
                      child: row,
                    ),
            );
          }),
          const SizedBox(height: 16),
        ],

        // Metadata
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 8),
        _MetaRow(
          icon: Icons.calendar_today,
          label: l.episodeMetaDate,
          value: _formatDate(info.uploadDate),
          theme: theme,
        ),
        _MetaRow(
          icon: Icons.schedule,
          label: l.episodeMetaDuration,
          value: info.durationString,
          theme: theme,
        ),
        // YouTube view/like counts hidden — snapshot data, not live-synced.
        // Re-enable once we have our own internal statistics.
        // _MetaRow(
        //   icon: Icons.visibility,
        //   label: 'Pregledi',
        //   value: _formatCount(info.viewCount),
        //   theme: theme,
        // ),
        // _MetaRow(
        //   icon: Icons.thumb_up,
        //   label: 'Lajkovi',
        //   value: _formatCount(info.likeCount),
        //   theme: theme,
        // ),
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

  // ignore: unused_element
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
