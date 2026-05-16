import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Web-only wrapper oko `navigator.mediaSession` API-ja.
///
/// Signal OS-u (iOS Now Playing, Android media notification, MacOS Control
/// Center) da je tab "playing media". Ima dva ključna efekta:
///
/// 1. **Background audio** — iOS Safari NE pauzira audio kad tab izgubi
///    fokus ili korisnik zaključa zaslon. Bez ovog (i bez SW), `<video>`
///    element pauzira čim tab ode u pozadinu.
/// 2. **Lock screen / Control Center kontrole** — play/pause/seek se
///    pokažu na lock screenu i Bluetooth headphone tipke rade.
///
/// Native (iOS/Android Flutter apps) ovo rješava `audio_service` paket;
/// ovaj fajl je web ekvivalent koji ne zahtjeva SW ni PWA install.

@JS('navigator')
external _Navigator get _nav;

extension type _Navigator._(JSObject _) implements JSObject {
  external _MediaSession? get mediaSession;
}

extension type _MediaSession._(JSObject _) implements JSObject {
  external set metadata(_MediaMetadata? value);
  external set playbackState(String value); // 'none' | 'paused' | 'playing'
  external void setActionHandler(String action, JSFunction? handler);
  external void setPositionState(_PositionState? state);
}

@JS('MediaMetadata')
extension type _MediaMetadata._(JSObject _) implements JSObject {
  external _MediaMetadata(JSObject init);
}

extension type _PositionState._(JSObject _) implements JSObject {
  external _PositionState({
    double? duration,
    double? playbackRate,
    double? position,
  });
}

extension type _Artwork._(JSObject _) implements JSObject {
  external _Artwork({String src, String? sizes, String? type});
}

bool get _supported => _nav.mediaSession != null;

void attachMetadataImpl({
  required String title,
  required String artist,
  String? album,
  String? artUrl,
}) {
  if (!_supported) return;
  try {
    final initObj = <String, dynamic>{
      'title': title,
      'artist': artist,
      if (album != null) 'album': album,
      if (artUrl != null)
        'artwork': [
          _Artwork(src: artUrl, sizes: '1200x630', type: 'image/jpeg'),
        ],
    }.jsify() as JSObject;
    _nav.mediaSession!.metadata = _MediaMetadata(initObj);
  } catch (_) {/* iOS Safari < 15 may throw — graceful no-op */}
}

void setPlaybackStateImpl(bool isPlaying) {
  if (!_supported) return;
  _nav.mediaSession!.playbackState = isPlaying ? 'playing' : 'paused';
}

void setPositionStateImpl({
  required double durationSec,
  required double positionSec,
  double playbackRate = 1.0,
}) {
  if (!_supported || durationSec <= 0) return;
  try {
    _nav.mediaSession!.setPositionState(_PositionState(
      duration: durationSec,
      position: positionSec.clamp(0, durationSec),
      playbackRate: playbackRate,
    ));
  } catch (_) {}
}

void setActionHandlersImpl({
  required void Function() onPlay,
  required void Function() onPause,
  required void Function(double position) onSeekTo,
  required void Function(double offset) onSeekBackward,
  required void Function(double offset) onSeekForward,
}) {
  if (!_supported) return;
  final ms = _nav.mediaSession!;
  ms.setActionHandler('play', (() => onPlay()).toJS);
  ms.setActionHandler('pause', (() => onPause()).toJS);
  ms.setActionHandler('seekto', ((JSObject details) {
    final dyn = details.dartify() as Map?;
    final t = dyn?['seekTime'];
    if (t is num) onSeekTo(t.toDouble());
  }).toJS);
  ms.setActionHandler('seekbackward', ((JSObject details) {
    final dyn = details.dartify() as Map?;
    final off = dyn?['seekOffset'];
    onSeekBackward((off is num) ? off.toDouble() : 10.0);
  }).toJS);
  ms.setActionHandler('seekforward', ((JSObject details) {
    final dyn = details.dartify() as Map?;
    final off = dyn?['seekOffset'];
    onSeekForward((off is num) ? off.toDouble() : 10.0);
  }).toJS);
}

void clearImpl() {
  if (!_supported) return;
  try {
    _nav.mediaSession!.metadata = null;
    for (final a in const ['play', 'pause', 'seekto', 'seekbackward', 'seekforward']) {
      _nav.mediaSession!.setActionHandler(a, null);
    }
  } catch (_) {}
}
