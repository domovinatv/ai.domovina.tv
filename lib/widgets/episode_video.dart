/// Zajednički video player wrapper za episode ekrane (web/mobile).
///
/// Nadogradnje nad golim media_kit `Video` widgetom — YouTube-like UX:
///  - klik na video toggle-a play/pause (media_kit default je OFF)
///  - dvoklik toggle-a fullscreen (desktop) / ±10s seek (mobile rubovi)
///  - titlovi iz diarized.srt (CC gumb, persisted pref) — rendamo ih SAMI
///    jer media_kit web subtitle path traži VTT i označen je "UNTESTED"
///  - fullscreen fix #1: ulazak u fullscreen na webu pauzira video jer se
///    <video> element re-parenta u novu Flutter rutu (DOM remove+insert =
///    pauza po HTML spec-u) → auto-resume nakon tranzicije
///  - fullscreen fix #2: Esc izađe iz browser fullscreena, ali media_kit
///    Flutter ruta ostane → fullscreenchange listener je sinkronizira
///  - YouTube keyboard kratice: Space/K, J/L ±10s, ←/→ ±5s, ↑/↓ glasnoća,
///    F fullscreen, M mute, C titlovi, Esc izlaz
///
/// Koriste ga VideoPanel (episode_screen) i _PlayerTab (episode_simple_screen).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/app_localizations.dart';
import '../models/podcast_summary.dart';
import '../models/speaker_timeline.dart';
import '../services/browser_fullscreen.dart';
import '../services/seek_undo.dart';
import '../services/subtitle_prefs.dart';
import 'playback_controls.dart';

/// Boje govornika po redoslijedu iz speakers liste — dijeli se s
/// VideoPanel speaker barom da fullscreen badge i bar budu konzistentni.
Map<String, Color> speakerColorsFor(
  ThemeData theme,
  List<SummarySpeaker> speakers,
) {
  final palette = [
    theme.colorScheme.primary,
    theme.colorScheme.tertiary,
    theme.colorScheme.secondary,
    theme.colorScheme.error,
  ];
  return {
    for (var i = 0; i < speakers.length; i++)
      speakers[i].id: palette[i % palette.length],
  };
}

class EpisodeVideo extends StatefulWidget {
  final Player player;
  final VideoController controller;

  /// Diarizirani transkript — izvor titlova i fullscreen speaker badge-a.
  final SpeakerTimeline? speakerTimeline;
  final List<SummarySpeaker> speakers;

  /// Ako je set, u control bar se dodaje gumb za YouTube embed mode
  /// (viša kvaliteta preko službenog YouTube playera).
  final VoidCallback? onYouTubeMode;

  /// Ponuda „vrati me gdje sam bio" nakon ručnog skoka po timelineu. Kad je
  /// zadana, pilula se renderira kroz `controls:` builder pa postoji i u
  /// media_kitovoj fullscreen ruti. Vlasnik je ekran (drži `Player`).
  final SeekUndo? seekUndo;

  const EpisodeVideo({
    super.key,
    required this.player,
    required this.controller,
    this.speakerTimeline,
    this.speakers = const [],
    this.onYouTubeMode,
    this.seekUndo,
  });

  @override
  State<EpisodeVideo> createState() => _EpisodeVideoState();
}

class _EpisodeVideoState extends State<EpisodeVideo> {
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();

  /// CC stanje — ValueNotifier da overlay i gumb (i njihove fullscreen
  /// kopije u media_kit ruti) dijele stanje bez setState-a preko ruta.
  final ValueNotifier<bool> _subtitlesOn = ValueNotifier<bool>(false);

  void Function()? _removeFsListener;

  /// Glasnoća prije mute-a (M kratica) za restore.
  double _volumeBeforeMute = 100;

  @override
  void initState() {
    super.initState();
    loadSubtitlesPref().then((saved) {
      if (mounted && saved != null) _subtitlesOn.value = saved;
    });
    _removeFsListener = addFullscreenChangeListener(_onBrowserFullscreenChange);
  }

  @override
  void dispose() {
    _removeFsListener?.call();
    _subtitlesOn.dispose();
    super.dispose();
  }

  /// Esc u browseru izađe iz native fullscreena bez znanja Fluttera —
  /// media_kit fullscreen ruta ostane "zarobljena". Detektiraj i popaj.
  void _onBrowserFullscreenChange() {
    if (isBrowserFullscreen) return;
    final vs = _videoKey.currentState;
    if (vs == null) return;
    try {
      if (vs.isFullscreen()) vs.exitFullscreen();
    } catch (_) {
      // contextNotifier još nije inicijaliziran — ignore.
    }
  }

  /// Web: re-parent <video> elementa u fullscreen rutu browser tretira kao
  /// remove+insert iz DOM-a i pauzira playback (HTML spec). Resume kratko
  /// nakon tranzicije ako je korisnik prije nje slušao. Dva pokušaja jer
  /// timing pause eventa ovisi o frame schedulingu.
  void _resumeAfterTransition(bool wasPlaying) {
    if (!wasPlaying) return;
    for (final delay in const [300, 900]) {
      Future<void>.delayed(Duration(milliseconds: delay), () {
        if (!mounted) return;
        try {
          if (!widget.player.state.playing) widget.player.play();
        } catch (_) {}
      });
    }
  }

  Future<void> _onEnterFullscreen() async {
    final wasPlaying = widget.player.state.playing;
    try {
      await defaultEnterNativeFullscreen();
    } catch (_) {
      // iPhone Safari ne podržava Element.requestFullscreen — Flutter
      // fullscreen ruta svejedno radi (in-app fullscreen).
    }
    _resumeAfterTransition(wasPlaying);
  }

  Future<void> _onExitFullscreen() async {
    final wasPlaying = widget.player.state.playing;
    try {
      await defaultExitNativeFullscreen();
    } catch (_) {}
    _resumeAfterTransition(wasPlaying);
  }

  void _toggleFullscreen() {
    final vs = _videoKey.currentState;
    if (vs == null) return;
    try {
      vs.isFullscreen() ? vs.exitFullscreen() : vs.enterFullscreen();
    } catch (_) {}
  }

  void _exitFullscreenIfAny() {
    final vs = _videoKey.currentState;
    if (vs == null) return;
    try {
      if (vs.isFullscreen()) vs.exitFullscreen();
    } catch (_) {}
  }

  void _seekRelative(Duration offset) {
    final pos = widget.player.state.position + offset;
    widget.player.seek(pos < Duration.zero ? Duration.zero : pos);
  }

  void _changeVolume(double delta) {
    final volume = (widget.player.state.volume + delta).clamp(0.0, 100.0);
    widget.player.setVolume(volume);
  }

  void _toggleMute() {
    final current = widget.player.state.volume;
    if (current > 0) {
      _volumeBeforeMute = current;
      widget.player.setVolume(0);
    } else {
      widget.player.setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 100);
    }
  }

  void _toggleSubtitles() {
    _subtitlesOn.value = !_subtitlesOn.value;
    saveSubtitlesPref(_subtitlesOn.value);
  }

  /// YouTube kratice: https://support.google.com/youtube/answer/7631406
  Map<ShortcutActivator, VoidCallback> get _keyboardShortcuts => {
        const SingleActivator(LogicalKeyboardKey.mediaPlay): () =>
            widget.player.play(),
        const SingleActivator(LogicalKeyboardKey.mediaPause): () =>
            widget.player.pause(),
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
            widget.player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            widget.player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.keyK): () =>
            widget.player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.keyJ): () =>
            _seekRelative(const Duration(seconds: -10)),
        const SingleActivator(LogicalKeyboardKey.keyL): () =>
            _seekRelative(const Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _seekRelative(const Duration(seconds: -5)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _seekRelative(const Duration(seconds: 5)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _changeVolume(5),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _changeVolume(-5),
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
        const SingleActivator(LogicalKeyboardKey.keyC): _toggleSubtitles,
        const SingleActivator(LogicalKeyboardKey.escape): _exitFullscreenIfAny,
      };

  Widget _subtitleButton() => _SubtitleToggleButton(
        enabled: _subtitlesOn,
        onToggle: _toggleSubtitles,
      );

  Widget? _youTubeButton() {
    final cb = widget.onYouTubeMode;
    if (cb == null) return null;
    final l = AppLocalizations.of(context);
    return IconButton(
      icon: const Icon(Icons.hd_outlined, color: Colors.white),
      tooltip: l.mediaYouTubeHigherQuality,
      onPressed: cb,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = speakerColorsFor(theme, widget.speakers);
    final timeline = widget.speakerTimeline;
    final ytButton = _youTubeButton();
    final undo = widget.seekUndo;

    // Brzina i „u pozadini" stoje lijevo od CC gumba, u obje trake; isti popis
    // ide i u `fullscreen:` varijantu teme pa kontrole postoje i u fullscreenu.
    //
    // PRELJEV — media_kit slaže `bottomButtonBar` u goli `Row` bez ikakve
    // zaštite, a desktop traka živi u 360 dp `VideoPanel` stupcu: sedam gumba
    // po 48 dp je 336 dp u 328 dp prostora (izmjereno: preljev od točno 8 dp,
    // vidi `test/playback_bar_layout_test.dart`). Zato tri mjere:
    //
    //  1. indikator pozicije umjesto `Spacer`-a dobiva `Expanded` +
    //     `scaleDown` — jedini elastičan element, skupi se umjesto da traka
    //     pukne (na 360 dp panelu praktički nestane; isto vrijeme piše i u
    //     panelovu redu odmah ispod slike, a u fullscreenu je cijelo);
    //  2. naša dva gumba idu u fiksnih 40 dp uz `scaleDown` — `VisualDensity`
    //     ovdje NE pomaže (M3 `IconButton` uzima gustoću iz svojih defaulta,
    //     ne iz `ThemeData`; izmjereno: ostaje 48 dp), a fiksna širina usput
    //     rješava i to što label brzine raste s vrijednošću („1×" vs „1,75×").
    Widget positionSlot(Widget indicator) => Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: indicator,
          ),
        );

    Widget compactSlot(Widget child) => SizedBox(
          width: 40,
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        );

    final speedButton = compactSlot(const SpeedCycleButton(onVideo: true));
    final backgroundButton = compactSlot(
      const BackgroundPlaybackButton(onVideo: true),
    );

    final desktopBottomBar = <Widget>[
      const MaterialDesktopPlayOrPauseButton(),
      const MaterialDesktopVolumeButton(),
      positionSlot(const MaterialDesktopPositionIndicator()),
      speedButton,
      backgroundButton,
      ?ytButton,
      if (timeline != null) _subtitleButton(),
      const MaterialDesktopFullscreenButton(),
    ];

    final mobileBottomBar = <Widget>[
      positionSlot(const MaterialPositionIndicator()),
      speedButton,
      backgroundButton,
      ?ytButton,
      if (timeline != null) _subtitleButton(),
      const MaterialFullscreenButton(),
    ];

    final fullscreenTopBar = <Widget>[
      if (timeline != null)
        _SpeakerBadge(
          player: widget.player,
          speakerTimeline: timeline,
          speakers: widget.speakers,
          speakerColors: colors,
        ),
    ];

    return MaterialDesktopVideoControlsTheme(
      normal: MaterialDesktopVideoControlsThemeData(
        playAndPauseOnTap: true,
        keyboardShortcuts: _keyboardShortcuts,
        bottomButtonBar: desktopBottomBar,
      ),
      fullscreen: MaterialDesktopVideoControlsThemeData(
        playAndPauseOnTap: true,
        keyboardShortcuts: _keyboardShortcuts,
        topButtonBar: fullscreenTopBar,
        bottomButtonBar: desktopBottomBar,
      ),
      child: MaterialVideoControlsTheme(
        normal: MaterialVideoControlsThemeData(
          seekOnDoubleTap: true,
          bottomButtonBar: mobileBottomBar,
        ),
        fullscreen: MaterialVideoControlsThemeData(
          seekOnDoubleTap: true,
          topButtonBar: fullscreenTopBar,
          bottomButtonBar: mobileBottomBar,
        ),
        child: Video(
          key: _videoKey,
          controller: widget.controller,
          onEnterFullscreen: _onEnterFullscreen,
          onExitFullscreen: _onExitFullscreen,
          controls: (state) => Stack(
            children: [
              if (timeline != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _SubtitleOverlay(
                      player: widget.player,
                      timeline: timeline,
                      enabled: _subtitlesOn,
                    ),
                  ),
                ),
              AdaptiveVideoControls(state),
              // Iznad kontrola u Z-osi jer mora primiti tap — media_kitov
              // control layer inače proguta klik (playAndPauseOnTap).
              // Kroz `controls:` builder pa pilula postoji i u fullscreen ruti.
              if (undo != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 72,
                  child: Center(
                    child: SeekUndoPill(
                      undo: undo,
                      onUndo: widget.player.seek,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CC gumb — dijeli ValueNotifier sa overlayem pa radi i u fullscreen ruti.
// ---------------------------------------------------------------------------

class _SubtitleToggleButton extends StatelessWidget {
  final ValueListenable<bool> enabled;
  final VoidCallback onToggle;

  const _SubtitleToggleButton({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: enabled,
      builder: (context, on, _) => IconButton(
        icon: Icon(
          on ? Icons.closed_caption : Icons.closed_caption_off_outlined,
          color: Colors.white,
        ),
        tooltip: on ? l.mediaSubtitlesOff : l.mediaSubtitlesOn,
        onPressed: onToggle,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subtitle overlay — YouTube stil: bottom-center, crna podloga, bijeli tekst.
// Renderira se kroz `controls` builder pa postoji i u fullscreen ruti.
// ---------------------------------------------------------------------------

class _SubtitleOverlay extends StatelessWidget {
  final Player player;
  final SpeakerTimeline timeline;
  final ValueListenable<bool> enabled;

  const _SubtitleOverlay({
    required this.player,
    required this.timeline,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: enabled,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, snapshot) {
            final cue = timeline.cueAt(snapshot.data ?? Duration.zero);
            if (cue == null || cue.text.isEmpty) {
              return const SizedBox.shrink();
            }
            return LayoutBuilder(builder: (context, constraints) {
              // Font skalira s veličinom playera: mali panel ~13px,
              // fullscreen 1080p ~24px — kao YouTube auto-size.
              final fontSize =
                  (constraints.maxWidth * 0.022).clamp(12.0, 24.0);
              return Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  // Tik iznad bottom control bara — YouTube pozicija (~10%
                  // od dna), skalira s visinom playera umjesto fiksnog 12%+36
                  // koji je na malom side-panelu gurao titl u sredinu slike.
                  padding: EdgeInsets.only(
                    bottom: (constraints.maxHeight * 0.06).clamp(8.0, 54.0) + 30,
                    left: 12,
                    right: 12,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.88,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(190),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        cue.text,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            });
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Speaker badge u fullscreen top baru (bivši _FullscreenSpeakerLabel iz
// video_panel.dart — premješten ovamo da ga dobije i simple screen).
// ---------------------------------------------------------------------------

class _SpeakerBadge extends StatelessWidget {
  final Player player;
  final SpeakerTimeline speakerTimeline;
  final List<SummarySpeaker> speakers;
  final Map<String, Color> speakerColors;

  const _SpeakerBadge({
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
              // Anonymous host (suggested_name == role) → samo roleLabel
              // umjesto duplog "Voditelj voditelj".
              if (speaker.displayName != null) ...[
                Text(
                  speaker.displayName!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (speaker.roleLabel.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    '· ${speaker.roleLabel}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ] else
                Text(
                  speaker.roleLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
