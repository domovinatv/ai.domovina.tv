import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Background audio/video playback — drzi media_kit Player zivim s OS-level
/// media sessionom dok je app u backgroundu (zakljucan zaslon, druga app, etc.).
///
/// Ponuda po platformi:
/// - **Android**: foreground media-playback service + notification s play/pause/
///   seek kontrolama, radi s Bluetooth tipkama i Android Auto.
/// - **iOS**: Now Playing info na lock screenu + Control Center, Bluetooth
///   remote kontrole, CarPlay.
/// - **Web**: no-op (browser sam hendla tab-level media kontrole).
///
/// Setup (jednokratno):
/// 1. `await BackgroundAudio.init();` u main() prije runApp().
/// 2. Platform config:
///    - `AndroidManifest.xml`: FOREGROUND_SERVICE_MEDIA_PLAYBACK permission
///      + AudioService + MediaButtonReceiver deklaracije.
///    - `Info.plist`: UIBackgroundModes = [audio].
///
/// Upotreba po ekranu:
/// ```dart
/// BackgroundAudio.instance.attach(
///   player: player, title: ..., artist: ..., artUri: ..., duration: ...);
/// // ... u dispose:
/// BackgroundAudio.instance.detach();
/// ```
class BackgroundAudio {
  BackgroundAudio._();
  static final BackgroundAudio instance = BackgroundAudio._();

  _MediaKitHandler? _handler;

  /// Jednokratni init — pozvati prije runApp().
  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      instance._handler = await AudioService.init(
        builder: () => _MediaKitHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'ai.domovina.audio',
          androidNotificationChannelName: 'DOMOVINA.ai player',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'mipmap/ic_launcher',
        ),
      );
    } catch (e) {
      debugPrint('BackgroundAudio init failed: $e');
    }
  }

  /// Registrira Player + metadata s media sessionom. Poziv zamjenjuje
  /// prethodni attachment. No-op na webu ili ako init nije uspio.
  Future<void> attach({
    required Player player,
    required String title,
    required String artist,
    String? artUri,
    Duration? duration,
  }) async {
    final h = _handler;
    if (h == null) return;
    try {
      await h.attachPlayer(
        player,
        MediaItem(
          id: '${title.hashCode}-${artist.hashCode}',
          title: title,
          artist: artist,
          artUri: artUri != null ? Uri.tryParse(artUri) : null,
          duration: duration,
        ),
      );
    } catch (e) {
      debugPrint('BackgroundAudio attach failed: $e');
    }
  }

  /// Zatvara sessionu i mice notification. Zvati u dispose ekrana.
  Future<void> detach() async {
    try {
      await _handler?.detachPlayer();
    } catch (e) {
      debugPrint('BackgroundAudio detach failed: $e');
    }
  }
}

class _MediaKitHandler extends BaseAudioHandler {
  Player? _player;
  final List<StreamSubscription<dynamic>> _subs = [];

  Future<void> attachPlayer(Player player, MediaItem item) async {
    await detachPlayer();
    _player = player;
    mediaItem.add(item);

    _subs.add(player.stream.playing.listen((playing) {
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.rewind,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.fastForward,
          ],
          systemActions: const {MediaAction.seek},
          processingState: AudioProcessingState.ready,
          playing: playing,
          updatePosition: player.state.position,
          speed: player.state.rate,
        ),
      );
    }));

    _subs.add(player.stream.position.listen((pos) {
      playbackState.add(playbackState.value.copyWith(updatePosition: pos));
    }));

    // Bez ovoga lock-screen scrub bar ekstrapolira poziciju na 1,0× pa pri
    // 1,5× vidno drifta između dva `updatePosition` eventa.
    _subs.add(player.stream.rate.listen((rate) {
      playbackState.add(
        playbackState.value.copyWith(
          updatePosition: player.state.position,
          speed: rate,
        ),
      );
    }));

    _subs.add(player.stream.duration.listen((dur) {
      final current = mediaItem.value;
      if (current != null && dur > Duration.zero) {
        mediaItem.add(current.copyWith(duration: dur));
      }
    }));
  }

  Future<void> detachPlayer() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _player = null;
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> seek(Duration position) async => _player?.seek(position);

  @override
  Future<void> fastForward() async {
    final p = _player;
    if (p == null) return;
    await p.seek(p.state.position + const Duration(seconds: 30));
  }

  @override
  Future<void> rewind() async {
    final p = _player;
    if (p == null) return;
    final target = p.state.position - const Duration(seconds: 10);
    await p.seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> stop() async {
    await _player?.pause();
    await detachPlayer();
    return super.stop();
  }
}
