/// Model za PLAĆENI sponzorski trenutak — `pinka_finance.public_live_moments`.
///
/// To je oglas koji je brand kupio na domovina.ai NAKON snimanja (samoposluga
/// na `/c/domovina-tv/oglasi`), a ne partner kojeg je autor sam doveo i koji je
/// ugrađen u snimku — taj je [SponsorsInVideo] (`sponsors_in_video.json`, ton
/// „Uz podršku"). Ovdje je ton „Sponzorirano · {brand}" s imenom platitelja
/// (DSA čl. 26). Odvojen izvor, odvojen model, odvojeni widgeti — ne spajati.
///
/// Ugovor: `domovina-api/docs/sponzorski-trenuci-ugovor.md` §3. View sadrži
/// samo trenutke koji su SADA uživo (`sold` ∧ `now() ∈ [live_from,
/// live_until)` ∧ nije povučen), pa klijent ne filtrira po stanju — samo po
/// vremenu, jer stranica zna stajati otvorena preko `live_until`.
library;

String? _nonEmpty(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

int? _int(Object? v) => v is num ? v.round() : null;

/// Ugovor jamči `https://`, ali gumb na ekranu ne smije ovisiti o tome da
/// backend nikad ne pogriješi: sve što nije https s hostom se odbacuje.
String? _httpsUrl(Object? v) {
  final s = _nonEmpty(v);
  if (s == null) return null;
  final uri = Uri.tryParse(s);
  if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) return null;
  return s;
}

/// Logo stiže s našeg Storagea; lokalni backend ga servira preko `http`.
String? _imageUrl(Object? v) {
  final s = _nonEmpty(v);
  if (s == null) return null;
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return null;
  if (!(uri.isScheme('https') || uri.isScheme('http'))) return null;
  return s;
}

/// Jedan kupljeni trenutak u epizodi, `[start, end)` u sekundama.
class SponsoredMoment {
  final String slotKey;
  final String youtubeId;
  final int start;
  final int end;

  /// Ime branda — ide u „Sponzorirano · {brand}" (≤ 60 znakova).
  final String brand;

  /// Jedna rečenica (≤ 120). Prikazuje se kao običan tekst, nikad kao HTML.
  final String? tagline;

  /// Uvijek `https://`; na webu ide s `rel="sponsored"`.
  final String? linkUrl;
  final String? logoUrl;
  final DateTime? liveFrom;
  final DateTime? liveUntil;

  const SponsoredMoment({
    required this.slotKey,
    required this.youtubeId,
    required this.start,
    required this.end,
    required this.brand,
    this.tagline,
    this.linkUrl,
    this.logoUrl,
    this.liveFrom,
    this.liveUntil,
  });

  /// Null kad red nema smislen raspon ili ime branda — takav se preskače
  /// (oznaka bez imena platitelja krši DSA čl. 26, pa je bolje ništa).
  static SponsoredMoment? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final start = _int(raw['start_sec']);
    final end = _int(raw['end_sec']);
    final brand = _nonEmpty(raw['brand']);
    final youtubeId = _nonEmpty(raw['youtube_id']);
    if (start == null || end == null || start < 0 || end <= start) return null;
    if (brand == null || youtubeId == null) return null;
    return SponsoredMoment(
      slotKey: _nonEmpty(raw['slot_key']) ?? '$youtubeId@$start',
      youtubeId: youtubeId,
      start: start,
      end: end,
      brand: brand,
      tagline: _nonEmpty(raw['tagline']),
      linkUrl: _httpsUrl(raw['link_url']),
      logoUrl: _imageUrl(raw['logo_url']),
      liveFrom: DateTime.tryParse(_nonEmpty(raw['live_from']) ?? ''),
      liveUntil: DateTime.tryParse(_nonEmpty(raw['live_until']) ?? ''),
    );
  }

  Duration get startPosition => Duration(seconds: start);
  Duration get endPosition => Duration(seconds: end);
  int get durationSeconds => end - start;

  /// Pozicija je u trenutku — poluotvoren raspon kao u ugovoru.
  bool contains(Duration position) =>
      position >= startPosition && position < endPosition;

  /// Je li zakup živ u trenutku [now]. View to već filtrira pri dohvatu, ali
  /// ekran epizode zna stajati otvoren satima.
  bool isLiveAt(DateTime now) {
    final from = liveFrom;
    final until = liveUntil;
    if (from != null && now.isBefore(from)) return false;
    if (until != null && !now.isBefore(until)) return false;
    return true;
  }

  /// `primjer.hr` iz `https://www.primjer.hr/x` — čitljivija oznaka gumba.
  String? get linkHost {
    final host = linkUrl == null ? null : Uri.tryParse(linkUrl!)?.host;
    if (host == null || host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

/// Svi živi plaćeni trenuci jedne epizode, poredani po početku.
class SponsoredMoments {
  final List<SponsoredMoment> moments;

  SponsoredMoments(this.moments);

  static final empty = SponsoredMoments(const []);

  /// Redovi iz `public_live_moments`. Pokvaren red se preskače, ostali
  /// preživljavaju; preklapanja (ugovor ih ne dopušta) zadržavaju prvi.
  factory SponsoredMoments.fromRows(Object? rows) {
    final list = <SponsoredMoment>[
      if (rows is List)
        for (final r in rows) ?SponsoredMoment.tryParse(r),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return SponsoredMoments(list);
  }

  bool get isEmpty => moments.isEmpty;
  bool get isNotEmpty => moments.isNotEmpty;

  /// Trenutak koji upravo svira, ili null.
  SponsoredMoment? activeAt(Duration position) {
    for (final m in moments) {
      if (m.contains(position)) return m;
    }
    return null;
  }

  /// Samo oni čiji je zakup živ u [now] (vidi [SponsoredMoment.isLiveAt]).
  SponsoredMoments liveAt(DateTime now) =>
      SponsoredMoments([for (final m in moments) if (m.isLiveAt(now)) m]);

  /// Oznake za članak, razvrstane po sekciji u koju pada POČETAK trenutka —
  /// zadnja sekcija s početkom ≤ `start`, a trenutak prije prve sekcije ide
  /// u prvu. Isto pravilo kao [SponsorsInVideo.marksBySection]: sidro je
  /// vrijeme, ne tekst.
  ///
  /// [sections] su (timestamp sekcije, početak u sekundama), poredane.
  Map<String, List<SponsoredMoment>> marksBySection(
    List<({String ts, int seconds})> sections,
  ) {
    if (sections.isEmpty || moments.isEmpty) return const {};
    final out = <String, List<SponsoredMoment>>{};
    for (final m in moments) {
      var ts = sections.first.ts;
      for (final sec in sections) {
        if (sec.seconds <= m.start) {
          ts = sec.ts;
        } else {
          break;
        }
      }
      (out[ts] ??= []).add(m);
    }
    return out;
  }

  /// Rasponi za pojas na seek baru. Računa se jednom: `_ChapterMarkerPainter`
  /// uspoređuje liste po identitetu, a panel se rebuilda ~5×/s.
  late final List<({Duration start, Duration end})> ranges = [
    for (final m in moments) (start: m.startPosition, end: m.endPosition),
  ];

  /// Najraniji `live_until` — trenutak kad treba ponovno filtrirati.
  DateTime? get nextExpiry {
    DateTime? out;
    for (final m in moments) {
      final u = m.liveUntil;
      if (u != null && (out == null || u.isBefore(out))) out = u;
    }
    return out;
  }
}
