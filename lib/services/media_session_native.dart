/// Native platforme — no-op. Native koristi `audio_service` za isto.
void attachMetadataImpl({
  required String title,
  required String artist,
  String? album,
  String? artUrl,
}) {}

void setPlaybackStateImpl(bool isPlaying) {}

void setPositionStateImpl({
  required double durationSec,
  required double positionSec,
  double playbackRate = 1.0,
}) {}

void setActionHandlersImpl({
  required void Function() onPlay,
  required void Function() onPause,
  required void Function(double position) onSeekTo,
  required void Function(double offset) onSeekBackward,
  required void Function(double offset) onSeekForward,
}) {}

void clearImpl() {}
