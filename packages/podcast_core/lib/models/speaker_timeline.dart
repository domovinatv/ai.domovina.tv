/// Vrijeme jedne izgovorene riječi unutar cue-a (ms od početka epizode).
class WordTiming {
  final int startMs;
  final int endMs;

  const WordTiming(this.startMs, this.endMs);
}

final _whitespace = RegExp(r'\s+');

/// Segment govora jednog govornika unutar diariziranog SRT transkripta.
class SpeakerSegment {
  final int startMs;
  final int endMs;
  final String speakerId; // npr. "SPEAKER_00", "SPEAKER_01"

  /// Tekst cue-a bez `[SPEAKER_XX]` prefiksa — koristi se za titlove.
  final String text;

  /// Vrijeme po riječi iz `words.json`, poravnato 1:1 s [tokens]. `null` kad
  /// datoteke nema ili se broj riječi ne slaže s tekstom (SRT je regeneriran
  /// nakon što je `words.json` izrađen) — tada nema isticanja, ne nagađamo.
  final List<WordTiming>? words;

  SpeakerSegment({
    required this.startMs,
    required this.endMs,
    required this.speakerId,
    this.text = '',
    this.words,
  });

  /// Riječi cue-a onako kako ih pipeline broji: tekst razlomljen po razmaku.
  /// Isti rez radi i `build_word_timings.js`, inače se indeksi razilaze.
  late final List<String> tokens = text.isEmpty
      ? const []
      : text.trim().split(_whitespace);

  SpeakerSegment withWords(List<WordTiming>? words) => SpeakerSegment(
    startMs: startMs,
    endMs: endMs,
    speakerId: speakerId,
    text: text,
    words: words,
  );

  /// Indeks riječi koja se izgovara u [ms], ili `null` prije prve riječi i
  /// kad nema vremena po riječi. U stanci između dviju riječi ostaje istaknuta
  /// prethodna, da isticanje ne treperi na svakom udahu.
  int? activeWordAt(int ms) {
    final w = words;
    if (w == null || w.isEmpty || ms < w.first.startMs) return null;
    int lo = 0, hi = w.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (w[mid].startMs <= ms) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Početak svake riječi u ms. S [words] je to stvarno vrijeme; bez njih se
  /// procjenjuje razmjerno broju znakova — dovoljno za listanje stranica
  /// titla, ali se NIKAD ne koristi za isticanje riječi.
  List<int> tokenStartsMs() {
    final w = words;
    if (w != null) return [for (final t in w) t.startMs];
    final toks = tokens;
    final total = toks.fold<int>(0, (n, t) => n + t.length + 1);
    final span = endMs - startMs;
    var acc = 0;
    final out = <int>[];
    for (final t in toks) {
      out.add(startMs + (total == 0 ? 0 : span * acc ~/ total));
      acc += t.length + 1;
    }
    return out;
  }
}

class SpeakerTimeline {
  final List<SpeakerSegment> segments;

  const SpeakerTimeline({required this.segments});

  /// Ima li ijedan cue vrijeme po riječi (tj. je li `words.json` stigao i
  /// poklopio se sa SRT-om).
  bool get hasWordTimings => segments.any((s) => s.words != null);

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

  /// Spoji `words.json` (vidi [parseWordTimings]) s cue-ovima. Cue se uparuje
  /// po početku (±1 ms, zaokruživanje SRT-a) i prihvaća SAMO ako se broj
  /// riječi točno slaže s [SpeakerSegment.tokens].
  SpeakerTimeline withWordTimings(Map<int, List<WordTiming>> byStart) {
    if (byStart.isEmpty) return this;
    List<WordTiming>? find(SpeakerSegment s) =>
        byStart[s.startMs] ?? byStart[s.startMs - 1] ?? byStart[s.startMs + 1];
    return SpeakerTimeline(
      segments: [
        for (final s in segments)
          switch (find(s)) {
            final w? when w.length == s.tokens.length => s.withWords(w),
            _ => s,
          },
      ],
    );
  }
}

/// Parsira `data/<id>/words.json`:
///
/// ```json
/// {"v": 1, "cues": [{"s": 0, "e": 15000, "w": [0, 120, 120, 300, …]}]}
/// ```
///
/// `s`/`e` su granice cue-a iz `diarized.srt` (ms), `w` je ravan niz parova
/// (početak, kraj) po riječi, istim redom kao riječi teksta cue-a. Neispravan
/// zapis se preskače, ne ruši parsiranje cijele datoteke.
Map<int, List<WordTiming>> parseWordTimings(Object? json) {
  final out = <int, List<WordTiming>>{};
  if (json is! Map || json['v'] != 1) return out;
  final cues = json['cues'];
  if (cues is! List) return out;
  for (final c in cues) {
    if (c is! Map) continue;
    final s = c['s'];
    final w = c['w'];
    if (s is! num || w is! List || w.length.isOdd || w.isEmpty) continue;
    final words = <WordTiming>[];
    var ok = true;
    for (var i = 0; i < w.length; i += 2) {
      final a = w[i], b = w[i + 1];
      if (a is! num || b is! num) {
        ok = false;
        break;
      }
      words.add(WordTiming(a.toInt(), b.toInt()));
    }
    if (ok) out[s.toInt()] = words;
  }
  return out;
}
