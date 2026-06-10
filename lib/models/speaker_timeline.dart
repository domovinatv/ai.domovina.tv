/// Segment govora jednog govornika unutar diariziranog SRT transkripta.
class SpeakerSegment {
  final int startMs;
  final int endMs;
  final String speakerId; // npr. "SPEAKER_00", "SPEAKER_01"

  /// Tekst cue-a bez `[SPEAKER_XX]` prefiksa — koristi se za titlove.
  final String text;

  const SpeakerSegment({
    required this.startMs,
    required this.endMs,
    required this.speakerId,
    this.text = '',
  });
}

class SpeakerTimeline {
  final List<SpeakerSegment> segments;

  const SpeakerTimeline({required this.segments});

  /// Vraca ID govornika koji govori u trenutku [pos].
  /// "Sticky": u prazninama između segmenata zadržava zadnjeg govornika.
  String? speakerAt(Duration pos) {
    final ms = pos.inMilliseconds;
    String? lastSpeaker;
    for (final seg in segments) {
      if (seg.startMs > ms) break;
      lastSpeaker = seg.speakerId;
    }
    return lastSpeaker;
  }

  /// Vraca cue (segment) tocno aktivan u trenutku [pos], ili null u praznini.
  /// Nije sticky — titl nestaje kad cue završi (kao na YouTubeu).
  /// Binary search: position stream fira ~5×/s nad ~2000 segmenata.
  SpeakerSegment? cueAt(Duration pos) {
    final ms = pos.inMilliseconds;
    int lo = 0, hi = segments.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final seg = segments[mid];
      if (ms < seg.startMs) {
        hi = mid - 1;
      } else if (ms >= seg.endMs) {
        lo = mid + 1;
      } else {
        return seg;
      }
    }
    return null;
  }
}
