library;

/// Jedno mjesto na mapi — kvadratić u 120×120 gridu ILI numerirano sjedalo.
/// Red iz `pinka_finance.public_slots` viewa (migracija 20260722120000).
///
/// Backend sloj je namjerno generički: grid i seat-mapa su isti problem
/// (fiksan skup jedinstveno identificiranih mjesta s atomarnim holdom preko
/// asinkrone uplate), pa ih dijeli isti model.
class PinkaSlot {
  /// Kanonski identitet mjesta. Grid: `'60:60'`. Seat-mapa: `'A:12:7'`.
  final String slotKey;

  /// Ono što korisnik vidi ("Sektor A, red 12, sjedalo 7"). Grid ga ne treba
  /// — tamo su koordinate same po sebi dovoljne.
  final String? label;

  /// Koordinate za crtanje. Grid i seat-mapa su oboje 2D mape.
  final int posX;
  final int posY;

  /// NFT token id (faza 2). Grid: `y * 120 + x`. Nepromjenjiv.
  final int tokenId;

  /// 0 = najjeftinija zona (vanjski rub / zadnji red). Veći indeks = skuplje.
  final int zoneIndex;
  final int priceCents;

  /// `free` | `blocked` | `held` | `sold` | `minted`.
  ///
  /// View već mapira ISTEKLI hold u `free`, pa klijent nikad ne vidi zombija
  /// i ne mora sam uspoređivati vrijeme.
  final String state;

  /// Popunjeno samo za `sold`/`minted`. Hold NE otkriva ništa — inače bi
  /// besplatna rezervacija bila vektor za oglašavanje bez plaćanja.
  final String? displayName;
  final String? message;
  final bool verified;

  final DateTime? mintedAt;
  final String? onchainTokenAddress;

  const PinkaSlot({
    required this.slotKey,
    required this.label,
    required this.posX,
    required this.posY,
    required this.tokenId,
    required this.zoneIndex,
    required this.priceCents,
    required this.state,
    required this.displayName,
    required this.message,
    required this.verified,
    required this.mintedAt,
    required this.onchainTokenAddress,
  });

  bool get isFree => state == 'free';
  bool get isHeld => state == 'held';
  bool get isTaken => state == 'sold' || state == 'minted';
  bool get isBlocked => state == 'blocked';

  /// Linearni indeks za mape širine [width] — zgodno kao ključ u `Map`
  /// dok se crta CustomPainterom.
  int indexFor(int width) => posY * width + posX;

  factory PinkaSlot.fromJson(Map<String, dynamic> json) {
    return PinkaSlot(
      slotKey: json['slot_key'] as String,
      label: json['label'] as String?,
      posX: (json['pos_x'] as num?)?.toInt() ?? 0,
      posY: (json['pos_y'] as num?)?.toInt() ?? 0,
      tokenId: (json['token_id'] as num?)?.toInt() ?? 0,
      zoneIndex: (json['zone_index'] as num?)?.toInt() ?? 0,
      priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
      state: (json['state'] as String?) ?? 'free',
      displayName: json['display_name'] as String?,
      message: json['message'] as String?,
      verified: (json['verified'] as bool?) ?? false,
      mintedAt: DateTime.tryParse((json['minted_at'] as String?) ?? ''),
      onchainTokenAddress: json['onchain_token_address'] as String?,
    );
  }
}

/// Cjenovna zona mape. Grid: koncentrični prsten. Seat-mapa: sektor.
class PinkaSlotZone {
  final int zoneIndex;
  final int priceCents;

  /// ARB ključ, ne gotov tekst — prijevod ostaje na klijentu (i18n pravilo).
  final String? labelKey;

  const PinkaSlotZone({
    required this.zoneIndex,
    required this.priceCents,
    required this.labelKey,
  });

  factory PinkaSlotZone.fromJson(Map<String, dynamic> json) {
    return PinkaSlotZone(
      zoneIndex: (json['zone_index'] as num?)?.toInt() ?? 0,
      priceCents: (json['price_cents'] as num?)?.toInt() ?? 0,
      labelKey: json['label_key'] as String?,
    );
  }
}

/// Mapa mjesta jedne kampanje. `null` znači da kampanja NEMA mapu — tada
/// se grid ne prikazuje (ili se pada natrag na legacy prikaz).
class PinkaSlotMap {
  final String id;

  /// `grid` | `seatmap`.
  final String kind;
  final int width;
  final int height;
  final List<PinkaSlotZone> zones;

  const PinkaSlotMap({
    required this.id,
    required this.kind,
    required this.width,
    required this.height,
    required this.zones,
  });

  bool get isGrid => kind == 'grid';

  factory PinkaSlotMap.fromJson(
    Map<String, dynamic> json,
    List<PinkaSlotZone> zones,
  ) {
    return PinkaSlotMap(
      id: json['id'] as String,
      kind: (json['kind'] as String?) ?? 'grid',
      width: (json['width'] as num?)?.toInt() ?? 120,
      height: (json['height'] as num?)?.toInt() ?? 120,
      zones: zones,
    );
  }
}

/// Mjesto je preoteto dok je korisnik birao. Tipizirano da ga panel razlikuje
/// od obične greške i može osvježiti mapu umjesto da prikaže sirovu poruku.
class PinkaSlotTaken implements Exception {
  final String? slotKey;
  PinkaSlotTaken([this.slotKey]);
  @override
  String toString() => 'PinkaSlotTaken(${slotKey ?? '?'})';
}
