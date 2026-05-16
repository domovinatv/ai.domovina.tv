import 'package:flutter/foundation.dart' show kIsWeb;
import 'media_session_web.dart' if (dart.library.io) 'media_session_native.dart'
    as platform;

/// Media Session API wrapper za web — drži tab "playing media" pa OS dopušta
/// background audio kad korisnik prijeđe na drugi tab, zaključa zaslon, ili
/// izađe iz browsera. Bez ovog (i bez SW), iOS Safari pauzira `<video>`
/// element čim tab izgubi fokus.
///
/// Native koristi `audio_service` paket (vidi [BackgroundAudio]).

class MediaSession {
  MediaSession._();

  /// Postavi metadata (title, artist, art) — pojavi se na lock screenu /
  /// Now Playing widgetu / OS media notification.
  static void attachMetadata({
    required String title,
    required String artist,
    String? album,
    String? artUrl,
  }) {
    if (!kIsWeb) return;
    platform.attachMetadataImpl(
      title: title,
      artist: artist,
      album: album,
      artUrl: artUrl,
    );
  }

  /// `'playing'` ili `'paused'` — iOS koristi za odluku oduzeti audio focus.
  static void setPlaybackState(bool isPlaying) {
    if (!kIsWeb) return;
    platform.setPlaybackStateImpl(isPlaying);
  }

  /// Update progress bara na lock screen / Now Playing. Throttling je
  /// preporučljiv (1Hz dovoljno).
  static void setPositionState({
    required Duration duration,
    required Duration position,
    double playbackRate = 1.0,
  }) {
    if (!kIsWeb) return;
    platform.setPositionStateImpl(
      durationSec: duration.inMilliseconds / 1000.0,
      positionSec: position.inMilliseconds / 1000.0,
      playbackRate: playbackRate,
    );
  }

  /// Registriraj handlere za lock-screen kontrole.
  /// onSeekTo: korisnik scrub-aju progress bar.
  /// onSeekBackward/Forward: tipke ±10s u Now Playing (default offset 10s).
  static void setActionHandlers({
    required void Function() onPlay,
    required void Function() onPause,
    required void Function(Duration position) onSeekTo,
    required void Function(Duration offset) onSeekBackward,
    required void Function(Duration offset) onSeekForward,
  }) {
    if (!kIsWeb) return;
    platform.setActionHandlersImpl(
      onPlay: onPlay,
      onPause: onPause,
      onSeekTo: (sec) => onSeekTo(Duration(milliseconds: (sec * 1000).round())),
      onSeekBackward: (off) =>
          onSeekBackward(Duration(milliseconds: (off * 1000).round())),
      onSeekForward: (off) =>
          onSeekForward(Duration(milliseconds: (off * 1000).round())),
    );
  }

  /// Očisti metadata + action handlere — pozvati pri dispose ekrana.
  static void clear() {
    if (!kIsWeb) return;
    platform.clearImpl();
  }
}
