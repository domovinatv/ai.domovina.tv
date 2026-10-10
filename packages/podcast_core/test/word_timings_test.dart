import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/models/speaker_timeline.dart';
import 'package:podcast_core/services/data_service.dart';
import 'package:podcast_core/widgets/subtitle_caption.dart';

/// Ugovor `data/<id>/words.json` ↔ `diarized.srt`.
///
/// Fixture je stvarni početak epizode `fln3cFCwHcs` (Mladi za domovinu, 4.10.):
/// SRT s CDN-a + `words.json` izrađen iz Speechmaticsova `.speechmatics.json`
/// referentnim poravnanjem (vidi `docs/2026-10-06-titlovi-rijec-po-rijec.md`).
const _utf8 = {'content-type': 'text/plain; charset=utf-8'};

void main() {
  setUp(DataService.resetMemoryForTest);

  Future<SpeakerTimeline?> load({required String srt, String? words}) {
    const svc = DataService(youtubeId: 'fln3cFCwHcs');
    return http.runWithClient(
      svc.loadSpeakerTimeline,
      () => MockClient((req) async {
        final path = req.url.path;
        // CDN šalje `charset=utf-8`; bez njega `http` čita latin1.
        if (path.endsWith('diarized.srt')) {
          return http.Response.bytes(utf8.encode(srt), 200, headers: _utf8);
        }
        if (path.endsWith('words.json') && words != null) {
          return http.Response.bytes(utf8.encode(words), 200, headers: _utf8);
        }
        return http.Response('Not Found', 404);
      }),
    );
  }

  final srt = File(
    'test/fixtures/fln3cFCwHcs_diarized_head.srt',
  ).readAsStringSync();
  final words = File(
    'test/fixtures/fln3cFCwHcs_words_head.json',
  ).readAsStringSync();

  test('stvarni words.json se poklopi sa svakim cue-om SRT-a', () async {
    final t = (await load(srt: srt, words: words))!;
    expect(t.segments, hasLength(6));
    for (final s in t.segments) {
      expect(s.words, isNotNull, reason: 'cue @${s.startMs}');
      expect(s.words!.length, s.tokens.length);
    }
    expect(t.hasWordTimings, isTrue);
  });

  test('aktivna riječ prati vrijeme i ostaje u stanci', () async {
    final cue = (await load(srt: srt, words: words))!.segments.first;
    final w = cue.words!;
    expect(cue.activeWordAt(w.first.startMs - 1), isNull);
    expect(cue.activeWordAt(w[3].startMs), 3);
    // Između kraja riječi i početka sljedeće ostaje istaknuta prethodna.
    expect(cue.activeWordAt(w[3].startMs + 1), 3);
    expect(cue.activeWordAt(cue.endMs - 1), w.length - 1);
    for (var i = 1; i < w.length; i++) {
      expect(w[i].startMs, greaterThanOrEqualTo(w[i - 1].startMs));
    }
  });

  test('bez words.json titl radi kao prije, bez isticanja', () async {
    final t = (await load(srt: srt))!;
    expect(t.segments, hasLength(6));
    expect(t.hasWordTimings, isFalse);
    expect(t.segments.first.activeWordAt(5000), isNull);
  });

  test('broj riječi se ne slaže → taj cue bez isticanja, ostali s', () {
    final t =
        SpeakerTimeline(
          segments: [
            SpeakerSegment(
              startMs: 0,
              endMs: 1000,
              speakerId: 'SPEAKER_00',
              text: 'Dobar dan',
            ),
            SpeakerSegment(
              startMs: 1000,
              endMs: 2000,
              speakerId: 'SPEAKER_00',
              text: 'svima vama',
            ),
          ],
        ).withWordTimings({
          0: const [WordTiming(0, 400)], // SRT regeneriran, riječ više
          1001: const [WordTiming(1000, 1400), WordTiming(1500, 1900)], // ±1 ms
        });
    expect(t.segments[0].words, isNull);
    expect(t.segments[1].words, hasLength(2));
  });

  test('neispravan words.json ne ruši ništa', () {
    expect(parseWordTimings(null), isEmpty);
    expect(parseWordTimings({'v': 2, 'cues': []}), isEmpty);
    expect(
      parseWordTimings({
        'v': 1,
        'cues': [
          {
            's': 0,
            'w': [0, 100, 200],
          }, // neparan
          {
            's': 5,
            'w': [0, 'x'],
          },
          {
            's': 9,
            'w': [10, 20],
          },
        ],
      }).keys,
      [9],
    );
  });

  test('stranice traka: svaka riječ točno jednom, poštuje broj redaka', () {
    final tokens = srt
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final pages = pageTokens(tokens, charsPerLine: 30, lines: 3);
    expect(pages.first.$1, 0);
    expect(pages.last.$2, tokens.length);
    for (var i = 1; i < pages.length; i++) {
      expect(pages[i].$1, pages[i - 1].$2);
    }
    for (final (from, to) in pages) {
      // Greedy prijelom na 30 znakova: najviše 3 retka.
      var lines = 1, len = 0;
      for (final t in tokens.sublist(from, to)) {
        final next = len == 0 ? t.length : len + 1 + t.length;
        if (len > 0 && next > 30) {
          lines++;
          len = t.length;
        } else {
          len = next;
        }
      }
      expect(lines, lessThanOrEqualTo(3));
    }
  });

  test('procjena vremena riječi bez words.json je monotona i u cue-u', () {
    final s = SpeakerSegment(
      startMs: 1000,
      endMs: 5000,
      speakerId: 'SPEAKER_00',
      text: 'jedan dva tri četiri',
    );
    final starts = s.tokenStartsMs();
    expect(starts.first, 1000);
    expect(starts.last, lessThan(5000));
    for (var i = 1; i < starts.length; i++) {
      expect(starts[i], greaterThan(starts[i - 1]));
    }
  });
}
