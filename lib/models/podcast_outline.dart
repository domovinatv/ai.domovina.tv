/// Model za .outline.json — tematske iteracije i poglavlja
class PodcastOutline {
  final List<OutlineIteration> iterations;

  const PodcastOutline({required this.iterations});

  factory PodcastOutline.fromJson(Map<String, dynamic> json) {
    return PodcastOutline(
      iterations: (json['iterations'] as List<dynamic>? ?? [])
          .map((i) => OutlineIteration.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}

class OutlineIteration {
  final int iterationNumber;
  final String startTime; // HH:MM:SS
  final String endTime;   // HH:MM:SS
  final String theme;
  final String reasonForCut;
  final List<OutlineChapter> chapters;

  const OutlineIteration({
    required this.iterationNumber,
    required this.startTime,
    required this.endTime,
    required this.theme,
    required this.reasonForCut,
    required this.chapters,
  });

  factory OutlineIteration.fromJson(Map<String, dynamic> json) {
    return OutlineIteration(
      iterationNumber: json['iteration_number'] as int? ?? 0,
      startTime: json['start_time'] as String? ?? '',
      endTime: json['end_time'] as String? ?? '',
      theme: json['theme'] as String? ?? '',
      reasonForCut: json['reason_for_cut'] as String? ?? '',
      chapters: (json['chapters'] as List<dynamic>? ?? [])
          .map((c) => OutlineChapter.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

class OutlineChapter {
  final String timestamp; // HH:MM:SS
  final String topic;

  const OutlineChapter({required this.timestamp, required this.topic});

  factory OutlineChapter.fromJson(Map<String, dynamic> json) {
    return OutlineChapter(
      timestamp: json['timestamp'] as String? ?? '',
      topic: json['topic'] as String? ?? '',
    );
  }

  /// Converts HH:MM:SS to total seconds
  int get totalSeconds {
    final parts = timestamp.split(':');
    if (parts.length == 3) {
      return int.parse(parts[0]) * 3600 +
          int.parse(parts[1]) * 60 +
          int.parse(parts[2]);
    }
    return 0;
  }
}
