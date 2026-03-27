/// Segment govora jednog govornika unutar diariziranog SRT transkripta.
class SpeakerSegment {
  final int startMs;
  final int endMs;
  final String speakerId; // npr. "SPEAKER_00", "SPEAKER_01"

  const SpeakerSegment({
    required this.startMs,
    required this.endMs,
    required this.speakerId,
  });
}

class SpeakerTimeline {
  final List<SpeakerSegment> segments;

  const SpeakerTimeline({required this.segments});

  /// Vraca ID govornika koji govori u trenutku [pos], ili null.
  String? speakerAt(Duration pos) {
    final ms = pos.inMilliseconds;
    for (final seg in segments) {
      if (ms >= seg.startMs && ms < seg.endMs) return seg.speakerId;
    }
    return null;
  }
}
