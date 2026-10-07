/// Izlog sponzorskih trenutaka — ponuda (`public_sponsor_moments`) i status
/// narudžbe (`rpc/sponsor_order_status`).
///
/// Ugovor: `domovina-api/docs/sponzorski-trenuci-ugovor.md` §2 i §6. Ovo je
/// strana KUPCA (karta, checkout, potvrda). Prikaz plaćenog trenutka gledatelju
/// je zaseban sloj, [SponsoredMoment].
///
/// Pravila iz ugovora koja ovaj model čuva:
/// - cijena je **bruto** i određuje je server; klijent je samo prikazuje;
/// - `slot_key` se ne parsira — `youtube_id` i `start_sec` su zasebne kolone;
/// - `held` ne otkriva ništa osim da netko upravo plaća.
library;

String? _nonEmpty(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

int? _int(Object? v) => v is num ? v.round() : null;

DateTime? _date(Object? v) => DateTime.tryParse(_nonEmpty(v) ?? '');

/// Stanje trenutka u izlogu.
enum SponsorSlotState {
  free,

  /// Netko upravo plaća (hold do isteka intenta, max 24 h).
  held,

  /// Prodano — `liveUntil` kaže do kada.
  sold,

  /// Ručno isključeno iz prodaje.
  blocked,

  /// Stanje koje ova verzija ne poznaje — tretira se kao nedostupno.
  unknown;

  static SponsorSlotState parse(Object? raw) => switch (raw) {
    'free' => free,
    'held' => held,
    'sold' => sold,
    'blocked' => blocked,
    _ => unknown,
  };

  bool get isBuyable => this == free;
}

/// Zona cijene. `zone_label_key` iz ugovora je ARB ključ; nepoznat ključ
/// postaje [other] i prikazuje se bez naziva zone.
enum SponsorZone {
  closing,
  body,
  opening,
  other;

  static SponsorZone parse(Object? raw) => switch (raw) {
    'sponsorZoneZatvaranje' => closing,
    'sponsorZoneTijelo' => body,
    'sponsorZoneOtvaranje' => opening,
    _ => other,
  };
}

/// Jedan trenutak u izlogu.
class SponsorOffer {
  final String campaignId;
  final String slotKey;
  final String youtubeId;
  final int start;
  final int end;

  /// Naslov sekcije članka koja počinje u trenutku.
  final String? title;
  final int zoneIndex;
  final SponsorZone zone;

  /// Bruto cijena u EUR centima (PDV uključen).
  final int priceCents;

  /// Koliko dana trenutak traje nakon uplate.
  final int runDays;
  final SponsorSlotState state;

  /// Do kada je zauzeto — samo kad je [SponsorSlotState.sold].
  final DateTime? liveUntil;

  const SponsorOffer({
    required this.campaignId,
    required this.slotKey,
    required this.youtubeId,
    required this.start,
    required this.end,
    required this.zoneIndex,
    required this.zone,
    required this.priceCents,
    required this.runDays,
    required this.state,
    this.title,
    this.liveUntil,
  });

  /// Null kad red nema ključ, epizodu, raspon ili cijenu — takav se ne nudi.
  static SponsorOffer? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final slotKey = _nonEmpty(raw['slot_key']);
    final youtubeId = _nonEmpty(raw['youtube_id']);
    final start = _int(raw['start_sec']);
    final end = _int(raw['end_sec']);
    final price = _int(raw['price_cents']);
    if (slotKey == null || youtubeId == null) return null;
    if (start == null || end == null || start < 0 || end <= start) return null;
    if (price == null || price <= 0) return null;
    return SponsorOffer(
      campaignId: _nonEmpty(raw['campaign_id']) ?? '',
      slotKey: slotKey,
      youtubeId: youtubeId,
      start: start,
      end: end,
      title: _nonEmpty(raw['title']),
      zoneIndex: _int(raw['zone_index']) ?? 0,
      zone: SponsorZone.parse(raw['zone_label_key']),
      priceCents: price,
      runDays: _int(raw['run_days']) ?? 0,
      state: SponsorSlotState.parse(raw['state']),
      liveUntil: _date(raw['live_until']),
    );
  }

  static List<SponsorOffer> listFromRows(Object? rows) => [
    if (rows is List)
      for (final r in rows) ?SponsorOffer.tryParse(r),
  ]..sort((a, b) => a.start.compareTo(b.start));

  int get durationSeconds => end - start;
  Duration get startPosition => Duration(seconds: start);
}

/// Stanje narudžbe (`contributions.state`).
enum SponsorOrderState {
  pending,
  paid,
  failed,
  expired,
  refunded,
  unknown;

  static SponsorOrderState parse(Object? raw) => switch (raw) {
    'pending' => pending,
    'paid' => paid,
    'failed' => failed,
    'expired' => expired,
    'refunded' => refunded,
    _ => unknown,
  };

  bool get isFinal => this != pending && this != unknown;
}

/// Trenutak unutar narudžbe (`slots[]` iz `sponsor_order_status`).
class SponsorOrderSlot {
  final String slotKey;
  final String youtubeId;
  final int start;
  final int end;

  /// Null nakon isteka zakupa (snapshot prodanih trenutaka nema `state`).
  final SponsorSlotState? state;
  final DateTime? liveFrom;
  final DateTime? liveUntil;

  const SponsorOrderSlot({
    required this.slotKey,
    required this.youtubeId,
    required this.start,
    required this.end,
    this.state,
    this.liveFrom,
    this.liveUntil,
  });

  static SponsorOrderSlot? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final slotKey = _nonEmpty(raw['slot_key']);
    final youtubeId = _nonEmpty(raw['youtube_id']);
    final start = _int(raw['start_sec']);
    final end = _int(raw['end_sec']);
    if (slotKey == null || youtubeId == null || start == null || end == null) {
      return null;
    }
    return SponsorOrderSlot(
      slotKey: slotKey,
      youtubeId: youtubeId,
      start: start,
      end: end,
      state: raw.containsKey('state')
          ? SponsorSlotState.parse(raw['state'])
          : null,
      liveFrom: _date(raw['live_from']),
      liveUntil: _date(raw['live_until']),
    );
  }
}

/// Odgovor `rpc/sponsor_order_status` (jedan red). Bez PII.
class SponsorOrderStatus {
  final SponsorOrderState state;

  /// Uplata manja od cijene → trenutak NIJE dodijeljen.
  final bool underpaid;
  final int amountCents;
  final int? amountReceivedCents;
  final DateTime? paidAt;

  /// Plaćeno, ali trenutak je u međuvremenu prodan drugome → ručni povrat.
  final bool slotUnassigned;
  final List<SponsorOrderSlot> slots;

  /// `pending` | `issued` | `sent` | `failed` | `skipped` | null.
  final String? invoiceState;
  final String? invoiceNumber;

  /// Vlasnik je povukao kreativu.
  final bool hidden;

  const SponsorOrderStatus({
    required this.state,
    required this.underpaid,
    required this.amountCents,
    this.amountReceivedCents,
    this.paidAt,
    this.slotUnassigned = false,
    this.slots = const [],
    this.invoiceState,
    this.invoiceNumber,
    this.hidden = false,
  });

  /// RPC vraća listu s jednim redom; prima i goli objekt.
  static SponsorOrderStatus? tryParse(Object? raw) {
    final row = raw is List ? (raw.isEmpty ? null : raw.first) : raw;
    if (row is! Map) return null;
    final slots = row['slots'];
    return SponsorOrderStatus(
      state: SponsorOrderState.parse(row['state']),
      underpaid: row['underpaid'] == true,
      amountCents: _int(row['amount_cents']) ?? 0,
      amountReceivedCents: _int(row['amount_received_cents']),
      paidAt: _date(row['paid_at']),
      slotUnassigned: row['slot_unassigned'] == true,
      slots: [
        if (slots is List)
          for (final s in slots) ?SponsorOrderSlot.tryParse(s),
      ],
      invoiceState: _nonEmpty(row['invoice_state']),
      invoiceNumber: _nonEmpty(row['invoice_number']),
      hidden: row['hidden'] == true,
    );
  }

  /// Plaćeno, dodijeljeno i nije povučeno — bez obzira na to traje li još.
  bool get isAssigned =>
      state == SponsorOrderState.paid &&
      !underpaid &&
      !slotUnassigned &&
      !hidden;

  /// Trenutak je stvarno uživo u [now]: dodijeljen i zakup još traje.
  /// Nakon isteka `state` ostaje `paid`, pa samo stanje nije dovoljno.
  bool isLiveAt(DateTime now) =>
      isAssigned &&
      slots.any((s) => s.liveUntil != null && now.isBefore(s.liveUntil!));
}
