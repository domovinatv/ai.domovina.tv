/// Titlovi s isticanjem izgovorene riječi + traka titla ispod playera.
///
/// Vrijeme po riječi dolazi iz `data/<id>/words.json` (Speechmatics, poravnat
/// s tekstom koji je Gemini uredio — vidi `SpeakerSegment.words`). Bez te
/// datoteke titl izgleda kao i prije: cijeli cue, bez isticanja.
///
/// Gdje se titl crta:
///  - preko slike (`EpisodeVideo` overlay) — desktop, tablet, mobitel u
///    landscapeu i svaki fullscreen;
///  - ISPOD slike ([SubtitleStrip]) — samo mobitel u portraitu, da tekst ne
///    prekriva ionako malen video.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';

import '../models/speaker_timeline.dart';
import '../services/subtitle_prefs.dart';

/// Mobitel u portraitu → titl ide ispod playera. Ista definicija „mobitela"
/// kao `_isPhoneLandscape` u `episode_screen.dart` (platforma I dimenzije),
/// samo za drugu orijentaciju — nizak desktop prozor ne smije dobiti traku.
bool subtitlesBelowPlayer(BuildContext context) {
  final platform = Theme.of(context).platform;
  if (platform != TargetPlatform.iOS && platform != TargetPlatform.android) {
    return false;
  }
  final size = MediaQuery.sizeOf(context);
  return size.height > size.width && size.shortestSide < 600;
}

// ---------------------------------------------------------------------------
// Sat reprodukcije
// ---------------------------------------------------------------------------

/// Position stream media_kita fira ~5×/s, a riječ traje 150–400 ms — isticanje
/// bi kasnilo i preskakalo riječi. Sat zato između dva događaja streama
/// ekstrapolira poziciju tickerom (uz brzinu reprodukcije), a rebuild radi
/// samo kad se promijeni [keyOf] (npr. aktivna riječ), ne na svaki frame.
///
/// Ticker poštuje `TickerMode`, pa zatvoren bočni panel ne troši ništa.
class CaptionClock extends StatefulWidget {
  final Player player;
  final Object? Function(int ms) keyOf;
  final Widget Function(BuildContext context, int ms) builder;

  const CaptionClock({
    super.key,
    required this.player,
    required this.keyOf,
    required this.builder,
  });

  @override
  State<CaptionClock> createState() => _CaptionClockState();
}

class _CaptionClockState extends State<CaptionClock>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final Stopwatch _sinceAnchor = Stopwatch();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playSub;
  int _anchorMs = 0;
  int _ms = 0;
  Object? _key;

  /// Najviše koliko smijemo ekstrapolirati bez potvrde streama — ako player
  /// zapne (buffering), titl ne smije pobjeći naprijed.
  static const int _maxExtrapolationMs = 600;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(CaptionClock old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      _unsubscribe();
      _subscribe();
    }
  }

  void _subscribe() {
    final p = widget.player;
    _anchor(p.state.position.inMilliseconds);
    _ms = _anchorMs;
    _key = widget.keyOf(_ms);
    _posSub = p.stream.position.listen((d) {
      _anchor(d.inMilliseconds);
      _update(_anchorMs);
    });
    _playSub = p.stream.playing.listen(_setRunning);
    _setRunning(p.state.playing);
  }

  void _unsubscribe() {
    _posSub?.cancel();
    _playSub?.cancel();
    if (_ticker.isActive) _ticker.stop();
  }

  void _anchor(int ms) {
    _anchorMs = ms;
    _sinceAnchor
      ..reset()
      ..start();
  }

  void _setRunning(bool playing) {
    if (playing && !_ticker.isActive) {
      _anchor(widget.player.state.position.inMilliseconds);
      _ticker.start();
    } else if (!playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration _) {
    final elapsed = _sinceAnchor.elapsedMilliseconds.clamp(
      0,
      _maxExtrapolationMs,
    );
    final rate = widget.player.state.rate;
    _update(_anchorMs + (elapsed * rate).round());
  }

  void _update(int ms) {
    _ms = ms;
    final key = widget.keyOf(ms);
    if (key != _key && mounted) {
      setState(() => _key = key);
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _ms);
}

// ---------------------------------------------------------------------------
// Isticanje
// ---------------------------------------------------------------------------

/// Boje titla. Izgovorene riječi i neizgovorene se razlikuju samo kad postoji
/// vrijeme po riječi — bez njega je cijeli tekst [spoken].
class CaptionColors {
  final Color spoken;
  final Color upcoming;
  final Color activeText;
  final Color activeFill;

  const CaptionColors({
    required this.spoken,
    required this.upcoming,
    required this.activeText,
    required this.activeFill,
  });
}

/// Tekst riječi `[from, to)` cue-a, s istaknutom riječi [active].
///
/// Isticanje mijenja SAMO boju i podlogu, nikad debljinu ni veličinu: riječ
/// koja se podeblja raširi redak i tekst se prelomi drukčije na svakoj
/// riječi — titl bi poskakivao dok ga čitaš.
TextSpan captionSpan(
  List<String> tokens, {
  required int from,
  required int to,
  required int? active,
  required TextStyle style,
  required CaptionColors colors,
}) {
  if (active == null) {
    return TextSpan(
      text: tokens.sublist(from, to).join(' '),
      style: style.copyWith(color: colors.spoken),
    );
  }
  final spans = <InlineSpan>[];
  final before = <String>[];
  final after = <String>[];
  for (var i = from; i < to; i++) {
    if (i < active) before.add(tokens[i]);
    if (i > active) after.add(tokens[i]);
  }
  if (before.isNotEmpty) {
    spans.add(
      TextSpan(
        text: '${before.join(' ')} ',
        style: TextStyle(color: colors.spoken),
      ),
    );
  }
  if (active >= from && active < to) {
    spans.add(
      TextSpan(
        text: tokens[active],
        style: TextStyle(
          color: colors.activeText,
          backgroundColor: colors.activeFill,
        ),
      ),
    );
  }
  if (after.isNotEmpty) {
    spans.add(
      TextSpan(
        text: '${active >= from ? ' ' : ''}${after.join(' ')}',
        style: TextStyle(color: colors.upcoming),
      ),
    );
  }
  return TextSpan(style: style, children: spans);
}

// ---------------------------------------------------------------------------
// Stranice titla (traka ispod playera)
// ---------------------------------------------------------------------------

/// Razlomi riječi u stranice od najviše [lines] redaka po [charsPerLine]
/// znakova. Vraća granice `[from, to)` svake stranice.
///
/// Traka ispod playera ima FIKSNU visinu (inače bi seek bar i sve ispod
/// skakali sa svakim cue-om), a cue zna imati 60 riječi. Umjesto da font
/// padne na 9 px, cue se lista po stranicama koje prate govor.
@visibleForTesting
List<(int, int)> pageTokens(
  List<String> tokens, {
  required int charsPerLine,
  required int lines,
}) {
  final pages = <(int, int)>[];
  var pageStart = 0;
  var line = 1;
  var lineLen = 0;
  for (var i = 0; i < tokens.length; i++) {
    final len = tokens[i].length;
    final next = lineLen == 0 ? len : lineLen + 1 + len;
    if (lineLen > 0 && next > charsPerLine) {
      if (line == lines) {
        pages.add((pageStart, i));
        pageStart = i;
        line = 1;
      } else {
        line++;
      }
      lineLen = len;
    } else {
      lineLen = next;
    }
  }
  if (pageStart < tokens.length) pages.add((pageStart, tokens.length));
  return pages;
}

/// Indeks zadnje riječi koja je počela do [ms] (0 prije prve).
int _tokenAt(List<int> starts, int ms) {
  var idx = 0;
  for (var i = 0; i < starts.length; i++) {
    if (starts[i] > ms) break;
    idx = i;
  }
  return idx;
}

/// Traka titla ispod playera — mobitel u portraitu ([subtitlesBelowPlayer]).
///
/// Prati isti CC prekidač kao overlay ([SubtitlesEnabled]); kad je CC
/// isključen, traka ne zauzima mjesto. Kad je uključen, visina je fiksna i u
/// stankama između cue-ova ostaje prazna — layout ispod se ne pomiče.
class SubtitleStrip extends StatelessWidget {
  final Player player;
  final SpeakerTimeline timeline;

  const SubtitleStrip({
    super.key,
    required this.player,
    required this.timeline,
  });

  static const int _lines = 3;
  static const double _fontSize = 15;
  static const double _lineHeight = 1.35;
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 8,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SubtitlesEnabled.instance,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final scaler = MediaQuery.textScalerOf(context);
        final style = DefaultTextStyle.of(context).style.merge(
          const TextStyle(
            fontSize: _fontSize,
            height: _lineHeight,
            fontWeight: FontWeight.w500,
          ),
        );
        final height =
            scaler.scale(_fontSize) * _lineHeight * _lines + _padding.vertical;
        final colors = CaptionColors(
          spoken: cs.onSurface,
          upcoming: cs.onSurfaceVariant.withAlpha(150),
          activeText: Colors.white,
          activeFill: cs.tertiary,
        );
        return Container(
          height: height,
          padding: _padding,
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: LayoutBuilder(
            builder: (context, c) => _StripText(
              player: player,
              timeline: timeline,
              maxWidth: c.maxWidth,
              maxHeight: c.maxHeight,
              style: style,
              scaler: scaler,
              colors: colors,
            ),
          ),
        );
      },
    );
  }
}

class _StripText extends StatefulWidget {
  final Player player;
  final SpeakerTimeline timeline;
  final double maxWidth;
  final double maxHeight;
  final TextStyle style;
  final TextScaler scaler;
  final CaptionColors colors;

  const _StripText({
    required this.player,
    required this.timeline,
    required this.maxWidth,
    required this.maxHeight,
    required this.style,
    required this.scaler,
    required this.colors,
  });

  @override
  State<_StripText> createState() => _StripTextState();
}

class _StripTextState extends State<_StripText> {
  /// Stranice po cue-u — računaju se jednom po cue-u i širini, ne 60×/s.
  SpeakerSegment? _pagedCue;
  double _pagedWidth = -1;
  List<(int, int)> _pages = const [];
  List<int> _starts = const [];

  int get _charsPerLine {
    // Prosječna širina znaka u ovom fontu, izmjerena na reprezentativnom
    // hrvatskom tekstu — samo polazna procjena, `_ensurePages` je provjeri.
    final tp = TextPainter(
      text: TextSpan(
        text: 'Dobar dan, ovo je primjer rečenice koja se govori.',
        style: widget.style,
      ),
      textDirection: TextDirection.ltr,
      textScaler: widget.scaler,
    )..layout();
    final avg = tp.width / 51;
    tp.dispose();
    return ((widget.maxWidth / avg).floor() - 1).clamp(12, 200);
  }

  void _ensurePages(SpeakerSegment cue) {
    if (identical(cue, _pagedCue) && _pagedWidth == widget.maxWidth) return;
    _pagedCue = cue;
    _pagedWidth = widget.maxWidth;
    // Procjena širine znaka zna promašiti (puno „m" i „š" u jednoj stranici),
    // pa se svaka stranica izmjeri; ako ijedna prelazi visinu trake, ponovi s
    // užim retkom. Titl se ne reže — vidi CLAUDE.md, „titlovi se ne režu".
    var chars = _charsPerLine;
    for (var attempt = 0; ; attempt++) {
      _pages = pageTokens(
        cue.tokens,
        charsPerLine: chars,
        lines: SubtitleStrip._lines,
      );
      if (attempt == 4 || _pages.every((p) => _fits(cue.tokens, p))) break;
      chars = (chars * 0.9).floor().clamp(8, 200);
    }
    _starts = cue.tokenStartsMs();
  }

  bool _fits(List<String> tokens, (int, int) page) {
    final tp = TextPainter(
      text: TextSpan(
        text: tokens.sublist(page.$1, page.$2).join(' '),
        style: widget.style,
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: widget.scaler,
    )..layout(maxWidth: widget.maxWidth);
    final fits = tp.height <= widget.maxHeight + 0.5;
    tp.dispose();
    return fits;
  }

  (SpeakerSegment, int, int?)? _state(int ms) {
    final cue = widget.timeline.cueAt(Duration(milliseconds: ms));
    if (cue == null || cue.tokens.isEmpty) return null;
    _ensurePages(cue);
    final at = _tokenAt(_starts, ms);
    final page = _pages.indexWhere((p) => at < p.$2);
    return (cue, page < 0 ? _pages.length - 1 : page, cue.activeWordAt(ms));
  }

  @override
  Widget build(BuildContext context) {
    return CaptionClock(
      player: widget.player,
      keyOf: (ms) {
        final s = _state(ms);
        return s == null ? null : (identityHashCode(s.$1), s.$2, s.$3);
      },
      builder: (context, ms) {
        final s = _state(ms);
        if (s == null) return const SizedBox.shrink();
        final (cue, page, active) = s;
        final (from, to) = _pages[page];
        return Text.rich(
          captionSpan(
            cue.tokens,
            from: from,
            to: to,
            active: active,
            style: widget.style,
            colors: widget.colors,
          ),
          textAlign: TextAlign.center,
          textScaler: widget.scaler,
        );
      },
    );
  }
}
