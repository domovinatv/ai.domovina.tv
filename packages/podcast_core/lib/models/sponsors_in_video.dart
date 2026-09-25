/// Model za `data/<id>/sponsors_in_video.json` — sponzori UGRAĐENI u snimku.
///
/// To su partneri koje je autor podcasta sam doveo i koji su omogućili
/// epizodu (spot, voditelj čita poruku, sponzorirana rubrika, zahvala). NISU
/// YouTubeovi oglasi i NISU dinamička sponzorstva koja se na domovina.ai kupuju
/// nakon snimanja — ta dolaze kao zaseban proizvod i zaseban izvor podataka,
/// pa ovaj sloj namjerno ne nosi generičko ime `Sponsors`.
///
/// Producent: `fetch.domovina.tv/detect_sponsors.js` (KORAK 9.85), ugovor u
/// `fetch.domovina.tv/docs/2026-09-23-sponzori-u-snimci.md`. Parser je
/// defenzivan: nepoznat `kind`/`role` postaje `unknown`/`other`, noviji
/// `schema_version` se pokuša pročitati, a pokvaren zapis se preskače umjesto
/// da sruši cijelu datoteku.
library;

/// Vrsta segmenta u snimci.
enum SponsorInVideoKind {
  /// Produciran oglas s posebnim glasom.
  spot,

  /// Voditelj čita poruku sponzora („Ovu epizodu podržava…").
  hostRead,

  /// Sponzorirana rubrika („Grickaj i biraj uz Plazmu").
  rubric,

  /// Jedna rečenica zahvale.
  mention,

  /// Autorovo poglavlje nazvano po sponzoru.
  chapter,

  /// Vrsta koju ova verzija aplikacije ne poznaje.
  unknown;

  static SponsorInVideoKind parse(Object? raw) => switch (raw) {
    'spot' => spot,
    'host_read' => hostRead,
    'rubric' => rubric,
    'mention' => mention,
    'chapter' => chapter,
    _ => unknown,
  };
}

/// Uloga sponzora u epizodi.
enum SponsorInVideoRole {
  sponsor,
  partner,

  /// „Voditeljicu odijeva…" — nema segmenata, samo kredit.
  wardrobe,

  /// „Opremanje studija pomogli…" — nema segmenata, samo kredit.
  studio,

  /// Uloga koju ova verzija aplikacije ne poznaje.
  other;

  static SponsorInVideoRole parse(Object? raw) => switch (raw) {
    'sponsor' => sponsor,
    'partner' => partner,
    'wardrobe' => wardrobe,
    'studio' => studio,
    _ => other,
  };

  /// Kredit (garderoba, studio) umjesto partnera čiju poruku netko čita.
  bool get isCredit => this == wardrobe || this == studio;
}

String? _nonEmpty(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

int? _int(Object? v) => v is num ? v.round() : null;

/// Jedan raspon u snimci koji pripada sponzoru.
class SponsorInVideoSegment {
  final SponsorInVideoKind kind;

  /// Sekunde u snimci (producent već dodaje ±1 s zalihe).
  final int start;
  final int end;

  /// Producent jamči pouzdane granice → smije se ponuditi „Poslušaj" s
  /// automatskim zaustavljanjem na [end].
  final bool playable;

  /// `high` | `medium` | `low`; null kad polje nedostaje.
  final String? confidence;

  /// Transkript segmenta (≤ 1200 znakova); null kad ga nema.
  final String? text;

  const SponsorInVideoSegment({
    required this.kind,
    required this.start,
    required this.end,
    this.playable = false,
    this.confidence,
    this.text,
  });

  /// Null kad segment nema smislen početak — takav se preskače.
  static SponsorInVideoSegment? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final start = _int(raw['start']);
    if (start == null || start < 0) return null;
    var end = _int(raw['end']) ?? start;
    if (end < start) end = start;
    final kind = SponsorInVideoKind.parse(raw['kind']);
    return SponsorInVideoSegment(
      kind: kind,
      start: start,
      end: end,
      // Nepoznatoj vrsti ne vjerujemo granice: ne znamo što bi „Poslušaj"
      // pustio, pa ostaje samo poveznica na trenutak.
      playable:
          raw['playable'] == true &&
          kind != SponsorInVideoKind.unknown &&
          end > start,
      confidence: _nonEmpty(raw['confidence']),
      text: _nonEmpty(raw['text']),
    );
  }

  Duration get startPosition => Duration(seconds: start);
  Duration get endPosition => Duration(seconds: end);
  int get durationSeconds => end - start;
}

/// Jedan sponzor (ili kredit) epizode.
class SponsorInVideo {
  /// Slug, stabilan unutar epizode. `_unattributed` = detektor zna da je
  /// segment sponzorski, ali ne zna čiji.
  final String id;
  final String? name;
  final SponsorInVideoRole role;
  final String? url;
  final String? instagram;

  /// Autorov reklamni tekst iz opisa (≤ 600 znakova).
  final String? blurb;
  final List<SponsorInVideoSegment> segments;

  const SponsorInVideo({
    required this.id,
    required this.role,
    this.name,
    this.url,
    this.instagram,
    this.blurb,
    this.segments = const [],
  });

  static const unattributedId = '_unattributed';

  /// Sponzor kojeg smijemo imenovati. Zapis bez imena se ne prikazuje.
  bool get isNamed => name != null && id != unattributedId;

  List<SponsorInVideoSegment> get playableSegments => [
    for (final s in segments)
      if (s.playable) s,
  ];

  static SponsorInVideo? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final segs = raw['segments'];
    return SponsorInVideo(
      id: _nonEmpty(raw['id']) ?? '',
      name: _nonEmpty(raw['name']),
      role: SponsorInVideoRole.parse(raw['role']),
      url: _httpUrl(raw['url']),
      instagram: _httpUrl(raw['instagram']),
      blurb: _nonEmpty(raw['blurb']),
      segments: [
        if (segs is List)
          for (final s in segs) ?SponsorInVideoSegment.tryParse(s),
      ]..sort((a, b) => a.start.compareTo(b.start)),
    );
  }

  /// Vanjska poveznica se prihvaća samo kao http(s) — sve ostalo (npr.
  /// `javascript:`) iz opisa epizode ne smije završiti na gumbu.
  static String? _httpUrl(Object? v) {
    final s = _nonEmpty(v);
    if (s == null) return null;
    final uri = Uri.tryParse(s);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    return uri.host.isEmpty ? null : s;
  }
}

/// Pouzdan raspon u snimci + sponzori kojima pripada (isti host_read zna biti
/// pripisan dvama sponzorima — tada je to JEDNA oznaka s oba imena).
typedef SponsorInVideoMark = ({
  List<SponsorInVideo> sponsors,
  SponsorInVideoSegment segment,
});

/// Sadržaj `sponsors_in_video.json` za jednu epizodu.
class SponsorsInVideo {
  final int schemaVersion;
  final String videoId;
  final List<SponsorInVideo> sponsors;

  const SponsorsInVideo({
    required this.schemaVersion,
    required this.videoId,
    this.sponsors = const [],
  });

  static const empty = SponsorsInVideo(schemaVersion: 1, videoId: '');

  factory SponsorsInVideo.fromJson(Map<String, dynamic> json) {
    final list = json['sponsors'];
    return SponsorsInVideo(
      schemaVersion: _int(json['schema_version']) ?? 1,
      videoId: _nonEmpty(json['video_id']) ?? '',
      sponsors: [
        if (list is List)
          for (final s in list) ?SponsorInVideo.tryParse(s),
      ],
    );
  }

  /// Sponzori koje prikazujemo — samo imenovani.
  List<SponsorInVideo> get named => [
    for (final s in sponsors)
      if (s.isNamed) s,
  ];

  /// Sekcija postoji samo kad ima barem jednog imenovanog sponzora.
  bool get hasNamed => sponsors.any((s) => s.isNamed);

  /// Oznake za članak: pouzdani rasponi imenovanih partnera (bez kredita),
  /// razvrstani po sekciji u koju PADA POČETAK raspona — zadnja sekcija s
  /// početkom ≤ `start`, a raspon prije prve sekcije ide u prvu. Tekst
  /// članka ne gledamo: AI zna oglas utopiti u susjednu sekciju (Ivin spot
  /// 1:39:23 opisan je tek u sekciji od 1:43:05), a vrijeme je točno.
  ///
  /// [sections] su (timestamp sekcije, početak u sekundama), poredane.
  Map<String, List<SponsorInVideoMark>> marksBySection(
    List<({String ts, int seconds})> sections,
  ) {
    if (sections.isEmpty) return const {};
    final byRange = <(int, int), SponsorInVideoMark>{};
    for (final s in named) {
      if (s.role.isCredit) continue;
      for (final seg in s.playableSegments) {
        final key = (seg.start, seg.end);
        final existing = byRange[key];
        byRange[key] = (
          sponsors: [...?existing?.sponsors, s],
          segment: existing?.segment ?? seg,
        );
      }
    }
    final out = <String, List<SponsorInVideoMark>>{};
    final marks = byRange.values.toList()
      ..sort((a, b) => a.segment.start.compareTo(b.segment.start));
    for (final m in marks) {
      var ts = sections.first.ts;
      for (final sec in sections) {
        if (sec.seconds <= m.segment.start) {
          ts = sec.ts;
        } else {
          break;
        }
      }
      (out[ts] ??= []).add(m);
    }
    return out;
  }

  /// Rasponi za oznake na vremenskoj crti playera: pouzdani segmenti
  /// imenovanih sponzora, bez duplikata (isti host_read zna biti pripisan
  /// dvama sponzorima).
  List<({Duration start, Duration end})> get playableRanges {
    final seen = <(int, int)>{};
    final out = <({Duration start, Duration end})>[];
    for (final s in named) {
      for (final seg in s.playableSegments) {
        if (seen.add((seg.start, seg.end))) {
          out.add((start: seg.startPosition, end: seg.endPosition));
        }
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }
}
