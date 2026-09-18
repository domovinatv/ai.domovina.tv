import 'package:flutter/material.dart';

/// Proporcionalne dimenzije za TV layout.
///
/// Problem koji ovo rješava: Android TV-i nekonzistentno reportiraju
/// `density`. Neki Full HD TV-i jave `density 1.0` (1920×1080 dp), drugi
/// `tvdpi` 1.33 (1444×812 dp), EON dev box density 2.0 (960×540 dp). Fiksne
/// dp vrijednosti zato izgledaju OK na jednoj klasi uređaja a "preglomazno"
/// ili "premaleno" na drugoj.
///
/// Strategija:
/// - **Horizontalni paddingi i max-width**: postotak širine ekrana (npr.
///   page padding = 3.5% širine; hero max 85% širine s capom). Tako rubovi
///   uvijek "dišu" jednako bez obzira na dp space.
/// - **Card / rail / hero visine i fontovi**: skala derivirana iz
///   `height / 540` (baseline = EON 540dp), clamp-ana na [0.85, 1.15] da
///   se ne digne ekstremno na 1080dp+ TV-ima. Vrijednosti su namjerno ~20%
///   manje od originalnih Faza 2-4 vrijednosti — Matija je javio
///   2026-05-27 da je na 55" Full HD home izgledao preglomazno.
///
/// Pozivatelj uvijek koristi `TvMetrics.of(context)`; instanca je jeftina
/// (sve vrijednosti su precomputane u konstruktoru) i mora se uzimati pri
/// svakom buildu jer screen size moze mijenjati (orijentacija, resize,
/// PiP exit).
class TvMetrics {
  /// Bezdimenzijska skala bazirana na `height / 540`. Koristi se za visine
  /// (rail, card) i font scaling. Clamp [0.85, 1.15] — na vrlo malim TV-ima
  /// (<460dp) ne smije nesta padati ispod 0.85, a na 1080p ne smije ići
  /// iznad 1.15 jer onda postaje opet "preglomazno" (vidi povijest).
  final double scale;

  /// Horizontalni page padding (appbar, hero, rail-ovi). 3.5% width, min 28,
  /// max 64. Na 960dp = 33.6dp; na 1444dp = 50dp; na 1920dp = 64dp (cap).
  final double pagePadH;

  /// Vertikalni padding ispod appbar-a (između appbar-a i hero-a).
  final double pagePadV;

  /// Razmak između hero-a i prvog rail-a — focused card scale 1.18 + glow
  /// trebaju ovaj prostor da ne ulaze u hero ispod.
  final double heroToRailGap;

  /// Razmak između susjednih rail-ova.
  final double sectionGap;

  /// Max širina hero card-a (centriran). 85% screen width, capana na 1100.
  final double heroMaxWidth;

  /// Max visina hero-a. 28% screen height, clamp 180-260. Smanjeno
  /// 2026-05-28 (bilo 38% / 200-340) jer je user javio da "Najbolji izbor"
  /// hero zauzima pola TV ekrana — premalo prostora ostaje rail-ovima.
  /// Vise od 1/4 screena hero ionako ne treba: na velikim TV-ima
  /// (1080dp) → 260dp = 24%, na malim (720dp) → 200dp = 28%.
  final double heroMaxHeight;

  /// Visina episode card rail-a — derivirana iz card content-a:
  /// thumb (16:9) + spacing + 3 reda bodySmall + spacing + 1 red labelSmall
  /// + safety buffer. Ne računa textScaler jer ga TvHomeScreen clamp-a na
  /// 1.0 (vidi MediaQuery override u build).
  final double episodeRailHeight;

  /// Visina channel card rail-a — derivirana iz card content-a:
  /// kvadratni avatar + spacing + 2 reda bodySmall + spacing + 1 red
  /// labelSmall + safety buffer.
  final double channelRailHeight;

  /// Širina jedne episode kartice u rail-u. Visina thumb-a derivirana 16:9.
  final double episodeCardWidth;

  /// Stranica kvadratnog channel avatara.
  final double channelCardSize;

  /// Spacing između kartica u rail-u.
  final double cardSpacing;

  factory TvMetrics.of(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return TvMetrics._derive(width: size.width, height: size.height);
  }

  factory TvMetrics._derive({required double width, required double height}) {
    final scale = (height / 540).clamp(0.85, 1.15);
    final episodeCardWidth = 132 * scale;
    final channelCardSize = 108 * scale;
    // Font line-heights (textScaler je clamp-an na 1.0 u TvHomeScreen):
    // - bodySmall    = 12sp × 1.2 height = 14.4dp (target)
    // - labelSmall   = 11sp × 1.2 height = 13.2dp (target)
    //
    // Stvarnost: Flutter Text rendering uvijek alocira space za font metric
    // ascender/descender bez obzira na `height: 1.2` override. Plus svaka
    // kartica je u `TvFocusable` koji ima `Border.all(width: 5)` UVIJEK
    // (transparent kad nije focused, ali width zauzima 10dp layout prostora).
    //
    // Buffer 50 = 10dp focus border + 40dp font metric / glow slack.
    // Bumped 2026-05-28 nakon novog 13px overflow-a — Flutter web ne respekta
    // pouzdano `height: 1.2` override na svakoj liniji; Roboto font metric
    // ascender+descender alocira nesto vise nego sto izgleda iz textStyle.
    //
    // maxLines podesen 2026-05-28 nakon screencap-a: korisnik ne zeli da
    // se title ni channel name ikad odsijecu. Na TV card width-u (152dp
    // @ scale 1.15) ~15 chars/line (12sp) / ~18 chars/line s letterSpacing
    // (11sp UPPERCASE eyebrow).
    //   episode card layout: thumb → eyebrow (channel UPPERCASE) → title
    //     eyebrow:  2 retka (long channel names kao "MOLITVENA ZAJEDNICA EHO")
    //     title:    5 redaka (~75 chars) — pokriva 99% naslova
    //   channel card layout: avatar → title → count
    //     title:    3 retka
    //     count:    1 redak
    const cardBuffer = 50.0;
    const episodeTitleLines = 5;
    const episodeEyebrowLines = 2;
    const channelTitleLines = 3;
    final episodeThumb = episodeCardWidth * 9 / 16;
    final episodeContent = episodeThumb +
        8 + // thumb → eyebrow
        episodeEyebrowLines * 13.2 +
        4 + // eyebrow → title
        episodeTitleLines * 14.4 +
        cardBuffer;
    final channelContent = channelCardSize +
        8 +
        channelTitleLines * 14.4 +
        2 +
        13.2 +
        cardBuffer;
    return TvMetrics._(
      scale: scale,
      pagePadH: (width * 0.035).clamp(28.0, 64.0),
      pagePadV: 16 * scale,
      heroToRailGap: 28 * scale,
      sectionGap: 24 * scale,
      heroMaxWidth: (width * 0.85).clamp(720.0, 1100.0),
      heroMaxHeight: (height * 0.28).clamp(180.0, 260.0),
      episodeRailHeight: episodeContent,
      channelRailHeight: channelContent,
      episodeCardWidth: episodeCardWidth,
      channelCardSize: channelCardSize,
      cardSpacing: 16 * scale,
    );
  }

  const TvMetrics._({
    required this.scale,
    required this.pagePadH,
    required this.pagePadV,
    required this.heroToRailGap,
    required this.sectionGap,
    required this.heroMaxWidth,
    required this.heroMaxHeight,
    required this.episodeRailHeight,
    required this.channelRailHeight,
    required this.episodeCardWidth,
    required this.channelCardSize,
    required this.cardSpacing,
  });
}
