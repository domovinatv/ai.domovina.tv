library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../main.dart' show log;
import '../../../../theme/app_theme.dart';
import '../models/pinka_public_contribution.dart';
import '../models/pinka_slot.dart';
import '../util/pinka_money.dart';
import 'pinka_common.dart';

/// Vizualni "zid" kvadratića: donacijom kupuješ svoj kvadratić. Crta se kao
/// JEDAN CustomPaint pass (nikad 14.400 widgeta); hover/selekcija idu kroz
/// zaseban overlay painter iza RepaintBoundaryja da ne repaintaju bazu.
///
/// **Dva izvora podataka, bez feature flaga:**
/// - [map] + [slots] ne-null → server je izvor istine. Mjesto se stvarno
///   rezervira (`slot_maps`/`slot_zones`/`slots`, migracija 20260722120000),
///   geometrija zona se izvodi iz mape, a stanja su tri: slobodno / `held` /
///   `sold`.
/// - [slots] `null` (kampanja nema mapu) → legacy prikaz: doprinosi se na
///   ćelije mapiraju deterministički na klijentu. Nitko ništa ne posjeduje,
///   ali zid izgleda živo. Uključivanje = seed mape na backendu.
class PinkaGridWall extends StatefulWidget {
  /// Legacy izvor (kad kampanja nema mapu mjesta).
  final List<PinkaPublicContribution> contributions;

  /// Mapa mjesta kampanje; `null` → legacy prikaz.
  final PinkaSlotMap? map;

  /// Zauzeta mjesta (view vraća samo `state <> 'free'`); `null` → legacy.
  final List<PinkaSlot>? slots;

  /// Mjesto koje host trenutno drži odabranim (`'60:60'`) — selekcijom
  /// upravlja host jer je ona vezana uz panel za uplatu.
  final String? selectedSlotKey;

  /// Tap na SLOBODNO mjesto (server mod).
  final void Function(String slotKey, int priceCents, String zoneName)?
      onSlotTap;

  /// Tap na slobodan kvadratić u LEGACY modu — samo predlaže iznos.
  final void Function(int amountCents, String zoneName)? onZoneTap;

  const PinkaGridWall({
    super.key,
    required this.contributions,
    this.map,
    this.slots,
    this.selectedSlotKey,
    this.onSlotTap,
    this.onZoneTap,
  });

  @override
  State<PinkaGridWall> createState() => _PinkaGridWallState();
}

const int _gridSide = 120;

/// Prsten zida u LEGACY geometriji: [startLayer] = udaljenost od ruba od koje
/// prsten počinje, [priceCents] = cijena kvadratića. Server mod ovo ne koristi
/// — tamo su prstenovi jednake debljine, izvedeni iz `slot_maps.width` i broja
/// zona (vidi `seed_grid_map`).
class _ZoneConfig {
  final int startLayer;
  final int priceCents;

  const _ZoneConfig(this.startLayer, this.priceCents);
}

const List<_ZoneConfig> _legacyZones = [
  _ZoneConfig(0, 100), // Vanjski pojas — 1 €
  _ZoneConfig(3, 200), // Zaštitni prsten — 2 €
  _ZoneConfig(6, 500), // Središnji pojas — 5 €
  _ZoneConfig(10, 1000), // Visoka zona — 10 €
  _ZoneConfig(14, 2000), // Zlatni krug — 20 €
  _ZoneConfig(19, 5000), // Poslovna zona — 50 €
  _ZoneConfig(25, 10000), // Direktorska zona — 100 €
  _ZoneConfig(32, 20000), // Prestiž — 200 €
  _ZoneConfig(41, 50000), // Elita — 500 €
  _ZoneConfig(51, 100000), // Jezgra — 1000 €
];

/// Prsten ćelije preko udaljenosti od ruba — legacy geometrija.
int _legacyZoneIndexOf(int x, int y) {
  final layer = [x, y, _gridSide - 1 - x, _gridSide - 1 - y]
      .reduce((a, b) => a < b ? a : b);
  for (var i = _legacyZones.length - 1; i >= 0; i--) {
    if (layer >= _legacyZones[i].startLayer) return i;
  }
  return 0;
}

/// Ćelije po prstenu (indeks = y*120+x, row-major) — legacy placement.
final Map<int, List<int>> _zoneCellsCache = {};

List<int> _zoneCells(int zone) {
  return _zoneCellsCache.putIfAbsent(zone, () {
    final cells = <int>[];
    for (var y = 0; y < _gridSide; y++) {
      for (var x = 0; x < _gridSide; x++) {
        if (_legacyZoneIndexOf(x, y) == zone) cells.add(y * _gridSide + x);
      }
    }
    return cells;
  });
}

/// FNV-1a 32-bit — stabilan hash id-a doprinosa za deterministički legacy
/// placement (bez Random/DateTime: isti popis uvijek daje isti raspored).
int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final cu in s.codeUnits) {
    h ^= cu;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Zona svake ćelije, row-major (indeks = y*w+x). Server: prstenovi JEDNAKE
/// debljine `(min(w,h)/2)/zoneCount`, identično `seed_grid_map`-u pa klijent
/// naplaćuje istu cijenu koju server traži. Legacy: stara `_legacyZones` tablica.
/// Dijele je zid i fullscreen picker da geometrija ostane jedan izvor istine.
Uint8List _computeZoneGrid(int w, int h, int zoneCount,
    {required bool serverMode}) {
  final out = Uint8List(w * h);
  final band = zoneCount > 0 ? (math.min(w, h) / 2.0) / zoneCount : 0.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      int zone;
      if (serverMode && zoneCount > 0) {
        final layer = math.min(math.min(x, y), math.min(w - 1 - x, h - 1 - y));
        zone = math.min((layer / band).floor(), zoneCount - 1);
      } else {
        zone = _legacyZoneIndexOf(x, y);
      }
      out[y * w + x] = zone;
    }
  }
  return out;
}

/// `label_key` → prevedeni naziv zone. Sirovi ključ se NIKAD ne prikazuje;
/// nepoznat ključ (nova zona na backendu) pada na redni broj.
String _zoneNameForKey(AppLocalizations l, String? key, int zone) {
  return switch (key) {
    'pinkaSlotZone0' => l.pinkaGridZoneOuterBelt,
    'pinkaSlotZone1' => l.pinkaGridZoneDefenseRing,
    'pinkaSlotZone2' => l.pinkaGridZoneMidBelt,
    'pinkaSlotZone3' => l.pinkaGridZoneHighZone,
    'pinkaSlotZone4' => l.pinkaGridZoneGoldenCircle,
    'pinkaSlotZone5' => l.pinkaGridZoneBusiness,
    'pinkaSlotZone6' => l.pinkaGridZoneExecutive,
    'pinkaSlotZone7' => l.pinkaGridZonePrestige,
    'pinkaSlotZone8' => l.pinkaGridZoneElite,
    // Jezgra se verzalizira u kodu (ARB vrijednosti bez ALL-CAPS-a).
    'pinkaSlotZone9' => l.pinkaGridZoneCore.toUpperCase(),
    _ => l.pinkaSlotZoneFallback(zone + 1),
  };
}

/// Boje zona — premium dvobojna paleta, izmjena po PAR/NEPAR prstenu.
///
/// Dvije nijanse (brand navy = „uplata" + prigušeno zlato) se izmjenjuju svaki
/// prsten pa je granica OŠTRA i kad je svjetlina slična (kritično na zoomu, gdje
/// je isti-ton-plave bilo nečitljivo). Svaka se i produbljuje prema središtu
/// (unutra = vrjednije). Samo dvije boje → premium, ne šareno. Zauzeto/held/
/// odabrano imaju svoje boje (crvena / prigušena crvena / bijeli obrub s halom).
/// Dijele je zid i fullscreen picker (jedan izvor istine).
List<Color> _zoneColors(int zoneCount) {
  const navyDeep = Color(0xFF0C2444); // vanjski navy (jeftinije)
  const navyLite = Color(0xFF5A8AD0); // navy prema središtu
  const goldDeep = Color(0xFF3E3115); // tamna bronca
  const goldLite = Color(0xFFCBA24E); // antikno zlato / šampanjac
  final n = math.max(zoneCount, 1);
  return List<Color>.generate(n, (i) {
    final t = n <= 1 ? 0.0 : i / (n - 1);
    return i.isEven
        ? Color.lerp(navyDeep, navyLite, t)!
        : Color.lerp(goldDeep, goldLite, t)!;
  });
}

/// Prigušena, opaque „rezervirano" crvena — jasno različita od pune prodane
/// crvene i od zona (navy/zlato), neovisno o pozadini.
Color _heldColor(ColorScheme cs) =>
    Color.lerp(cs.tertiary, cs.surfaceContainerHighest, 0.5)!;

class _PinkaGridWallState extends State<PinkaGridWall> {
  /// Server mod: ćelija (y*w+x) → mjesto koje NIJE slobodno.
  Map<int, PinkaSlot> _slotByCell = const {};

  /// Legacy mod: ćelija → doprinos koji je "drži".
  Map<int, PinkaPublicContribution> _cellOwners = const {};

  /// Zona svake ćelije, predizračunata — painter je čita bez računanja po
  /// ćeliji, a hit-test i cijena idu kroz isti izvor.
  Uint8List _zoneOf = Uint8List(0);

  /// Potpis podataka/geometrije — jeftina usporedba u [CustomPainter.shouldRepaint].
  String _signature = '';
  String _geometrySignature = '';

  int? _hoverCell;
  int? _legacySelectedCell;

  bool get _serverMode => widget.map != null && widget.slots != null;
  int get _w => widget.map?.width ?? _gridSide;
  int get _h => widget.map?.height ?? _gridSide;

  List<PinkaSlotZone> get _zones => widget.map?.zones ?? const [];

  @override
  void initState() {
    super.initState();
    _rebuildGeometry();
    _rebuildData();
  }

  @override
  void didUpdateWidget(covariant PinkaGridWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildGeometry();
    _rebuildData();
  }

  /// Geometrija zona. Server: prstenovi JEDNAKE debljine
  /// `(min(w,h)/2) / brojZona`, identično `seed_grid_map`-u — inače bi klijent
  /// naplaćivao drugu cijenu nego što server traži. Legacy: stara tablica.
  void _rebuildGeometry() {
    final sig = _serverMode
        ? 'srv:${_w}x$_h:${_zones.length}'
        : 'legacy:$_gridSide';
    if (sig == _geometrySignature && _zoneOf.isNotEmpty) return;
    _geometrySignature = sig;

    final zoneCount = _serverMode ? _zones.length : _legacyZones.length;
    _zoneOf = _computeZoneGrid(_w, _h, zoneCount, serverMode: _serverMode);
  }

  void _rebuildData() {
    if (_serverMode) {
      _placeSlots();
    } else {
      _placeContributions();
    }
  }

  /// Server mod: mjesta dolaze s koordinatama — nema ničega za "rasporediti".
  void _placeSlots() {
    final slots = widget.slots!;
    final sig = 'srv:${slots.length}:'
        '${slots.map((s) => '${s.slotKey}${s.state}').join(',').hashCode}';
    if (sig == _signature) return;
    _signature = sig;

    final byCell = <int, PinkaSlot>{};
    for (final s in slots) {
      if (s.posX < 0 || s.posX >= _w || s.posY < 0 || s.posY >= _h) continue;
      byCell[s.indexFor(_w)] = s;
    }
    _slotByCell = byCell;
    _cellOwners = const {};
    final held = byCell.values.where((s) => s.isHeld).length;
    log('PinkaGridWall: server mod — ${byCell.length} zauzetih mjesta'
        ' (${byCell.length - held} prodanih, $held rezerviranih)');
  }

  /// Legacy mod: hash id-a doprinosa unutar najskupljeg prstena koji iznos
  /// pokriva. Izgleda kao vlasništvo, ali nitko ništa ne posjeduje — zato je
  /// ovo samo fallback dok kampanja nema mapu mjesta.
  void _placeContributions() {
    final sig = 'legacy:${widget.contributions.map((c) => c.id).join(',')}';
    if (sig == _signature) return;
    _signature = sig;

    // Kanonski redoslijed po id-u — placement ne ovisi o redoslijedu s API-ja.
    final sorted = [...widget.contributions]
      ..sort((a, b) => a.id.compareTo(b.id));
    final owners = <int, PinkaPublicContribution>{};
    var spills = 0;
    var unplaced = 0;
    for (final c in sorted) {
      // Najskuplji prsten koji si iznos može priuštiti; ispod 1 € → rub.
      var zone = 0;
      for (var i = _legacyZones.length - 1; i >= 0; i--) {
        if (c.amountCents >= _legacyZones[i].priceCents) {
          zone = i;
          break;
        }
      }
      var placed = false;
      for (var z = zone; z >= 0 && !placed; z--) {
        final cells = _zoneCells(z);
        final start = _fnv1a(c.id) % cells.length;
        for (var probe = 0; probe < cells.length; probe++) {
          final cell = cells[(start + probe) % cells.length];
          if (!owners.containsKey(cell)) {
            owners[cell] = c;
            placed = true;
            break;
          }
        }
        if (!placed) spills++; // prsten pun → prelij u prvi jeftiniji
      }
      if (!placed) unplaced++;
    }
    _cellOwners = owners;
    _slotByCell = const {};
    log('PinkaGridWall: legacy mod — mapirano ${owners.length}/'
        '${widget.contributions.length} doprinosa'
        '${spills > 0 ? ', $spills prelijevanja u jeftiniji prsten' : ''}'
        '${unplaced > 0 ? ', $unplaced NEsmješteno (zid pun)' : ''}');
  }

  // ── Zone: cijena + naziv ─────────────────────────────────────────────────

  int _zoneAt(int cell) => cell < _zoneOf.length ? _zoneOf[cell] : 0;

  int _priceOfZone(int zone) {
    if (_serverMode) {
      return zone < _zones.length ? _zones[zone].priceCents : 0;
    }
    return _legacyZones[zone.clamp(0, _legacyZones.length - 1)].priceCents;
  }

  String _zoneName(AppLocalizations l, int zone) {
    final key = _serverMode && zone < _zones.length
        ? _zones[zone].labelKey
        : 'pinkaSlotZone$zone';
    return _zoneNameForKey(l, key, zone);
  }

  // ── Hit test / interakcija ───────────────────────────────────────────────

  int? _cellAt(Offset local, Size size) {
    final cellW = size.width / _w;
    final cellH = size.height / _h;
    if (cellW <= 0 || cellH <= 0) return null;
    final x = (local.dx / cellW).floor().clamp(0, _w - 1);
    final y = (local.dy / cellH).floor().clamp(0, _h - 1);
    return y * _w + x;
  }

  /// Odabrana ćelija: u server modu je vlasnik selekcije HOST (vezana je uz
  /// panel za uplatu), u legacyju lokalno stanje.
  int? get _selectedCell {
    if (!_serverMode) return _legacySelectedCell;
    final key = widget.selectedSlotKey;
    if (key == null) return null;
    final parts = key.split(':');
    if (parts.length != 2) return null;
    final x = int.tryParse(parts[0]);
    final y = int.tryParse(parts[1]);
    if (x == null || y == null) return null;
    return y * _w + x;
  }

  void _setHover(int? cell) {
    if (cell == _hoverCell) return; // setState samo na promjenu ćelije
    setState(() => _hoverCell = cell);
  }

  void _onTap(int? cell) {
    if (cell == null) return;
    final l = AppLocalizations.of(context);

    if (_serverMode) {
      final slot = _slotByCell[cell];
      if (slot != null) {
        if (slot.isBlocked) return;
        // Hold NE otkriva tko drži mjesto (besplatna rezervacija ne smije
        // biti kanal za oglašavanje) — samo poruka da je privremeno zauzeto.
        if (slot.isHeld) {
          _showHeldSheet(l);
        } else {
          _showSlotSheet(l, slot);
        }
        return;
      }
      final zone = _zoneAt(cell);
      final x = cell % _w;
      final y = cell ~/ _w;
      widget.onSlotTap?.call('$x:$y', _priceOfZone(zone), _zoneName(l, zone));
      return;
    }

    final owner = _cellOwners[cell];
    if (owner != null) {
      _showOwnerSheet(owner);
      return;
    }
    final zone = _zoneAt(cell);
    setState(() => _legacySelectedCell = cell);
    widget.onZoneTap?.call(_priceOfZone(zone), _zoneName(l, zone));
  }

  /// Bottom sheet za PRODANO mjesto — isti vizualni jezik kao kartica na
  /// PinkaWallList zidu (ime + iznos + poruka).
  void _showSlotSheet(AppLocalizations l, PinkaSlot slot) {
    _sheet(
      title: l.pinkaGridTakenTitle,
      name: slot.displayName ?? l.pinkaAnonymous,
      amountCents: slot.priceCents,
      message: slot.message,
    );
  }

  void _showOwnerSheet(PinkaPublicContribution c) {
    final l = AppLocalizations.of(context);
    _sheet(
      title: l.pinkaGridTakenTitle,
      name: c.displayNameOrAnon(l),
      amountCents: c.amountCents,
      message: c.message,
    );
  }

  /// Rezervirano mjesto: privremeno stanje, ne vlasništvo — reci to izravno
  /// umjesto da tap izgleda kao da se ništa nije dogodilo.
  void _showHeldSheet(AppLocalizations l) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.pinkaSlotHeldTitle,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(l.pinkaSlotHeldBody,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  void _sheet({
    required String title,
    required String name,
    required int amountCents,
    String? message,
  }) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${fmtEur(amountCents)} €',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
                if (message != null && message.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  PinkaLinkify(
                    text: message.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);

    final zoneCount = _serverMode ? _zones.length : _legacyZones.length;
    // Prodano = tertiary (crveni akcent), rezervirano = polovični tint prema
    // tertiary (očito privremeno stanje).
    final zoneColors = _zoneColors(zoneCount);
    final rim = AppTheme.brandRim(theme.brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _serverMode ? l.pinkaSlotIntro : l.pinkaGridIntro,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.fromBorderSide(
              rim == BorderSide.none
                  ? BorderSide(color: cs.outlineVariant)
                  : rim,
            ),
          ),
          child: AspectRatio(
            aspectRatio: _w / _h,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                return MouseRegion(
                  onEnter: (e) => _setHover(_cellAt(e.localPosition, size)),
                  onHover: (e) => _setHover(_cellAt(e.localPosition, size)),
                  onExit: (_) => _setHover(null),
                  // Očisti hover na SVAKI dodir/klik: onHover ne pali dok je
                  // gumb pritisnut, pa nakon brzog drag-a stara hover ćelija
                  // ostane osvijetljena pored prave selekcije („dva odabrana").
                  child: Listener(
                    onPointerDown: (_) => _setHover(null),
                    child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onTap(_cellAt(d.localPosition, size)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Baza (svih w*h ćelija) iza RepaintBoundaryja —
                        // repainta se samo kad se promijene mjesta/tema,
                        // NE na hover.
                        RepaintBoundary(
                          child: CustomPaint(
                            isComplex: true,
                            painter: _GridPainter(
                              width: _w,
                              height: _h,
                              zoneOf: _zoneOf,
                              zoneColors: zoneColors,
                              soldColor: cs.tertiary,
                              heldColor: _heldColor(cs),
                              blockedColor: cs.surfaceContainerHighest,
                              soldCells: _cellsInState(_SlotDraw.sold),
                              heldCells: _cellsInState(_SlotDraw.held),
                              blockedCells: _cellsInState(_SlotDraw.blocked),
                              signature: '$_signature|$_geometrySignature',
                            ),
                          ),
                        ),
                        CustomPaint(
                          painter: _OverlayPainter(
                            width: _w,
                            height: _h,
                            hoverCell: _hoverCell,
                            selectedCell: _selectedCell,
                          ),
                        ),
                        // Fullscreen picker: zoom + pan ispod nišana za
                        // precizan odabir (i razgledavanje zauzetih). Samo
                        // server mod — legacy nema pravih mjesta za birati.
                        if (_serverMode)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: _ExpandButton(onTap: _openPicker),
                          ),
                      ],
                    ),
                  ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 18,
          child: _statusLabel(theme, l),
        ),
      ],
    );
  }

  /// Otvori fullscreen picker; rezultat (slot_key) prolazi istim putem kao tap
  /// na slobodnu ćeliju — host zaključa iznos na cijenu zone.
  Future<void> _openPicker() async {
    if (!_serverMode) return;
    final chosen = await showPinkaGridPicker(
      context,
      map: widget.map!,
      slots: widget.slots!,
      initialSlotKey: widget.selectedSlotKey,
    );
    if (chosen == null || !mounted) return;
    final parts = chosen.split(':');
    if (parts.length != 2) return;
    final x = int.tryParse(parts[0]);
    final y = int.tryParse(parts[1]);
    if (x == null || y == null) return;
    final zone = _zoneAt(y * _w + x);
    widget.onSlotTap?.call(
        chosen, _priceOfZone(zone), _zoneName(AppLocalizations.of(context), zone));
  }

  Set<int> _cellsInState(_SlotDraw want) {
    if (!_serverMode) {
      // Legacy: sve "zauzeto" je prodano — druga stanja ne postoje.
      return want == _SlotDraw.sold ? _cellOwners.keys.toSet() : const {};
    }
    final out = <int>{};
    _slotByCell.forEach((cell, s) {
      final draw = s.isHeld
          ? _SlotDraw.held
          : s.isBlocked
              ? _SlotDraw.blocked
              : _SlotDraw.sold;
      if (draw == want) out.add(cell);
    });
    return out;
  }

  /// Redak ispod grida: hover → stanje mjesta, inače uputa za tap.
  Widget _statusLabel(ThemeData theme, AppLocalizations l) {
    final style = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final cell = _hoverCell;
    if (cell == null) {
      return Text(l.pinkaGridTapHint,
          style: style, overflow: TextOverflow.ellipsis);
    }

    if (_serverMode) {
      final slot = _slotByCell[cell];
      if (slot != null) {
        if (slot.isHeld) {
          return Text(l.pinkaSlotStatusHeld,
              style: style?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis);
        }
        if (slot.isBlocked) {
          return Text(l.pinkaSlotStatusBlocked,
              style: style, overflow: TextOverflow.ellipsis);
        }
        return Text(
          '${slot.displayName ?? l.pinkaAnonymous}'
          ' · ${fmtEur(slot.priceCents)} €',
          style: style?.copyWith(
              color: theme.colorScheme.tertiary, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        );
      }
    } else {
      final owner = _cellOwners[cell];
      if (owner != null) {
        return Text(
          '${owner.displayNameOrAnon(l)} · ${fmtEur(owner.amountCents)} €',
          style: style?.copyWith(
              color: theme.colorScheme.tertiary, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        );
      }
    }

    final zone = _zoneAt(cell);
    return Text(
      l.pinkaGridZonePriceLabel(
          _zoneName(l, zone), fmtEur(_priceOfZone(zone))),
      style: style?.copyWith(fontWeight: FontWeight.w600),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Kako se ćelija crta. `held` je namjerno vizualno odvojen od `sold`: bez
/// toga djelomično plaćen zid izgleda lažno pun.
enum _SlotDraw { sold, held, blocked }

/// Baza zida: sve ćelije u jednom paint passu (port BillboardPainter).
class _GridPainter extends CustomPainter {
  final int width;
  final int height;
  final Uint8List zoneOf;
  final List<Color> zoneColors;
  final Color soldColor;
  final Color heldColor;
  final Color blockedColor;
  final Set<int> soldCells;
  final Set<int> heldCells;
  final Set<int> blockedCells;

  /// Potpis podataka + geometrije — jeftina usporedba u [shouldRepaint].
  final String signature;

  _GridPainter({
    required this.width,
    required this.height,
    required this.zoneOf,
    required this.zoneColors,
    required this.soldColor,
    required this.heldColor,
    required this.blockedColor,
    required this.soldCells,
    required this.heldCells,
    required this.blockedCells,
    required this.signature,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / width;
    final cellH = size.height / height;
    const spacing = 0.5;
    final paint = Paint()..style = PaintingStyle.fill;
    // Rub oko rezerviranog mjesta crtamo samo kad ćelija ima dovoljno piksela
    // da se rub uopće vidi (na 120×120 u uskom stupcu ćelija je ~3 px).
    final drawHeldRim = cellW >= 4 && heldCells.isNotEmpty;
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = soldColor;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final cell = y * width + x;
        final Color color;
        if (soldCells.contains(cell)) {
          color = soldColor;
        } else if (heldCells.contains(cell)) {
          color = heldColor;
        } else if (blockedCells.contains(cell)) {
          color = blockedColor;
        } else {
          final z = cell < zoneOf.length ? zoneOf[cell] : 0;
          color = zoneColors[z < zoneColors.length ? z : zoneColors.length - 1];
        }
        paint.color = color;
        final rect = Rect.fromLTWH(
          x * cellW + spacing,
          y * cellH + spacing,
          cellW - spacing * 2,
          cellH - spacing * 2,
        );
        canvas.drawRect(rect, paint);
        if (drawHeldRim && heldCells.contains(cell)) {
          canvas.drawRect(rect, rimPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    return oldDelegate.signature != signature ||
        oldDelegate.soldCells.length != soldCells.length ||
        oldDelegate.heldCells.length != heldCells.length ||
        oldDelegate.soldColor != soldColor ||
        oldDelegate.zoneColors.first != zoneColors.first ||
        oldDelegate.zoneColors.last != zoneColors.last;
  }
}

/// Overlay iznad baze: samo hover + odabrana ćelija (2 strokea max) —
/// repainta se na svaki pomak ćelije, ali NE dira bazni pass.
class _OverlayPainter extends CustomPainter {
  final int width;
  final int height;
  final int? hoverCell;
  final int? selectedCell;

  _OverlayPainter({
    required this.width,
    required this.height,
    required this.hoverCell,
    required this.selectedCell,
  });

  Rect _cellRect(int cell, Size size) {
    final cellW = size.width / width;
    final cellH = size.height / height;
    final x = cell % width;
    final y = cell ~/ width;
    return Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Bijeli obrub s tamnim halom — čitljiv i na navy i na zlatnim zonama
    // (neovisan o temi; croBlue-na-navy je prije nestajao).
    if (selectedCell != null) {
      final r = _cellRect(selectedCell!, size).inflate(1);
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..color = Colors.black.withValues(alpha: 0.55),
      );
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = Colors.white,
      );
    }
    if (hoverCell != null && hoverCell != selectedCell) {
      canvas.drawRect(
        _cellRect(hoverCell!, size),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter oldDelegate) {
    return oldDelegate.hoverCell != hoverCell ||
        oldDelegate.selectedCell != selectedCell;
  }
}

/// Gumb koji otvara fullscreen picker (prekriva gornji-desni kut zida).
class _ExpandButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ExpandButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.zoom_out_map, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(l.pinkaSlotPickerOpen,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Otvori fullscreen picker; vraća odabrani `slot_key` ili `null` (odustao).
Future<String?> showPinkaGridPicker(
  BuildContext context, {
  required PinkaSlotMap map,
  required List<PinkaSlot> slots,
  String? initialSlotKey,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (_) => _PinkaGridPickerScreen(
        map: map,
        slots: slots,
        initialSlotKey: initialSlotKey,
      ),
    ),
  );
}

/// Fullscreen odabir kvadratića: grid se pinch-zoomira i povlači (pan) ispod
/// FIKSNOG nišana na sredini ekrana — ćelija pod nišanom je kandidat, „Potvrdi"
/// je zaključa. Kao biranje pina na karti: nema sukoba gesti (pan/zoom idu
/// InteractiveVieweru, nišan stoji), precizno je i usput razgledaš zauzete.
///
/// Grid child je TOČNO veličine viewporta (kvadrat `side`), pa je scale 1
/// uvijek savršen fit; InteractiveViewer skalira taj layer za zoom.
class _PinkaGridPickerScreen extends StatefulWidget {
  final PinkaSlotMap map;
  final List<PinkaSlot> slots;
  final String? initialSlotKey;

  const _PinkaGridPickerScreen({
    required this.map,
    required this.slots,
    this.initialSlotKey,
  });

  @override
  State<_PinkaGridPickerScreen> createState() => _PinkaGridPickerScreenState();
}

class _PinkaGridPickerScreenState extends State<_PinkaGridPickerScreen> {
  final _tc = TransformationController();
  late final Uint8List _zoneOf;
  late final Map<int, PinkaSlot> _slotByCell;
  late final List<Color> _colors;

  /// Ćelija pod nišanom, ili `null` kad je nišan iznad praznog platna (izvan
  /// mreže) — grid „lebdi" u širem 2D prostoru (Figma-style), pa nišan smije
  /// biti i pored njega.
  int? _candidate;

  /// Puni pravokutni viewport (landscape na desktopu, portrait na mobitelu) i
  /// logička strana kvadratnog grida koji u njemu lebdi.
  Size? _viewport;
  double _gridPx = 0;
  bool _inited = false;

  int get _w => widget.map.width;
  int get _h => widget.map.height;
  List<PinkaSlotZone> get _zones => widget.map.zones;

  @override
  void initState() {
    super.initState();
    _zoneOf = _computeZoneGrid(_w, _h, _zones.length, serverMode: true);
    final byCell = <int, PinkaSlot>{};
    for (final s in widget.slots) {
      if (s.posX < 0 || s.posX >= _w || s.posY < 0 || s.posY >= _h) continue;
      byCell[s.indexFor(_w)] = s;
    }
    _slotByCell = byCell;
    _colors = _zoneColors(_zones.length);
    _candidate = _cellForKey(widget.initialSlotKey) ??
        (_h ~/ 2) * _w + (_w ~/ 2); // default: sredina (jezgra), korigira _onTransform
    _tc.addListener(_onTransform);
  }

  int? _cellForKey(String? key) {
    if (key == null) return null;
    final p = key.split(':');
    if (p.length != 2) return null;
    final x = int.tryParse(p[0]);
    final y = int.tryParse(p[1]);
    if (x == null || y == null || x < 0 || x >= _w || y < 0 || y >= _h) {
      return null;
    }
    return y * _w + x;
  }

  @override
  void dispose() {
    _tc.removeListener(_onTransform);
    _tc.dispose();
    super.dispose();
  }

  /// Ćelija pod nišanom = scena u središtu PRAVOKUTNOG viewporta → koordinate.
  /// Grid lebdi u širem 2D prostoru, pa nišan može pasti izvan mreže → `null`.
  void _onTransform() {
    final vp = _viewport;
    final g = _gridPx;
    if (vp == null || g <= 0) return;
    final scene = _tc.toScene(Offset(vp.width / 2, vp.height / 2));
    int? cell;
    if (scene.dx >= 0 && scene.dx < g && scene.dy >= 0 && scene.dy < g) {
      final cx = (scene.dx / g * _w).floor().clamp(0, _w - 1);
      final cy = (scene.dy / g * _h).floor().clamp(0, _h - 1);
      cell = cy * _w + cx;
    }
    if (cell != _candidate) setState(() => _candidate = cell);
  }

  /// Afini transform v' = scale·v + (tx,ty), column-major (translacija u
  /// zadnjem stupcu). Ručno da izbjegnemo deprecirane Matrix4.translate/scale.
  static Matrix4 _affine(double scale, double tx, double ty) => Matrix4(
        scale, 0, 0, 0, //
        0, scale, 0, 0, //
        0, 0, 1, 0, //
        tx, ty, 0, 1, //
      );

  /// Grid (kvadrat `g`) centriran u pravokutnom viewportu. S početnim odabirom:
  /// uleti (scale 3) i centriraj tu ćeliju; inače lagani „fit s marginom" (0.85)
  /// da se odmah vidi kako grid lebdi u širem prostoru (Figma-osjećaj).
  Matrix4 _initialMatrix(Size vp, double g) {
    final focus = _cellForKey(widget.initialSlotKey);
    if (focus != null) {
      const s = 3.0;
      final sx = ((focus % _w) + 0.5) / _w * g;
      final sy = ((focus ~/ _w) + 0.5) / _h * g;
      return _affine(s, vp.width / 2 - s * sx, vp.height / 2 - s * sy);
    }
    const s = 0.85;
    return _affine(s, vp.width / 2 - s * g / 2, vp.height / 2 - s * g / 2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        title: Text(l.pinkaSlotPickerTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final vp = Size(constraints.maxWidth, constraints.maxHeight);
                // Grid je kvadrat strane min(W,H) i LEBDI u punom pravokutnom
                // viewportu (landscape/portrait), ne reže se u kvadrat.
                final g = math.min(vp.width, vp.height);
                _viewport = vp;
                _gridPx = g;
                if (!_inited) {
                  _inited = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _tc.value = _initialMatrix(vp, g);
                    _onTransform();
                  });
                }
                return Stack(
                  children: [
                    // Puni pravokutnik = platno; grid (kvadrat) lebdi unutra.
                    Positioned.fill(
                      child: InteractiveViewer(
                      transformationController: _tc,
                      // Manje od 1 dopušta odmicanje/razgledavanje u širem
                      // prostoru (Figma-osjećaj), više za precizan odabir.
                      minScale: 0.4,
                      maxScale: 10,
                      // Beskonačna margina = slobodan 2D pan u svim smjerovima;
                      // grid lebdi u „beskonačnom" platnu.
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      // constrained:false → child zadržava svoju kvadratnu
                      // veličinu `g` umjesto da ga viewport rastegne u pravokutnik.
                      constrained: false,
                      child: SizedBox(
                        width: g,
                        height: g,
                        child: Stack(
                          children: [
                            RepaintBoundary(
                              child: CustomPaint(
                                isComplex: true,
                                size: Size(g, g),
                                painter: _GridPainter(
                                  width: _w,
                                  height: _h,
                                  zoneOf: _zoneOf,
                                  zoneColors: _colors,
                                  soldColor: cs.tertiary,
                                  heldColor: _heldColor(cs),
                                  blockedColor: cs.surfaceContainerHighest,
                                  soldCells: _cells(_SlotDraw.sold),
                                  heldCells: _cells(_SlotDraw.held),
                                  blockedCells: _cells(_SlotDraw.blocked),
                                  signature: 'picker:${_slotByCell.length}',
                                ),
                              ),
                            ),
                            CustomPaint(
                              size: Size(g, g),
                              painter: _PickerCandidatePainter(
                                width: _w,
                                height: _h,
                                cell: _candidate,
                                // Bijela s tamnim halom — čitljiva i na navy i
                                // na zlatnim zonama.
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ),
                    // Fiksni nišan na sredini pravokutnika — u SCREEN prostoru,
                    // ne transformira se s gridom.
                    const IgnorePointer(
                      child: Center(
                        child: SizedBox(
                            width: 48, height: 48, child: _Reticle()),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _bottomBar(theme, l),
        ],
      ),
    );
  }

  Set<int> _cells(_SlotDraw want) {
    final out = <int>{};
    _slotByCell.forEach((cell, s) {
      final draw = s.isHeld
          ? _SlotDraw.held
          : s.isBlocked
              ? _SlotDraw.blocked
              : _SlotDraw.sold;
      if (draw == want) out.add(cell);
    });
    return out;
  }

  Widget _bottomBar(ThemeData theme, AppLocalizations l) {
    final cs = theme.colorScheme;
    final cell = _candidate;

    // Nišan iznad praznog platna (izvan mreže): pozovi korisnika da ga vrati.
    if (cell == null) {
      return _bottomBarShell(
        theme,
        cs,
        icon: Icons.control_camera,
        iconColor: cs.onSurfaceVariant,
        status: l.pinkaSlotPickerOffGrid,
        coords: null,
        buttonLabel: l.pinkaSlotPickerOffGrid,
        onPressed: null,
      );
    }

    final x = cell % _w, y = cell ~/ _w;
    final zone = cell < _zoneOf.length ? _zoneOf[cell] : 0;
    final price = zone < _zones.length ? _zones[zone].priceCents : 0;
    final zoneName = _zoneNameForKey(
        l, zone < _zones.length ? _zones[zone].labelKey : null, zone);
    final slot = _slotByCell[cell];
    final free = slot == null || slot.isFree;
    final held = slot != null && slot.isHeld;
    final blocked = slot != null && slot.isBlocked;

    final String status;
    if (free) {
      status = l.pinkaGridZonePriceLabel(zoneName, fmtEur(price));
    } else if (held) {
      status = l.pinkaSlotStatusHeld;
    } else if (blocked) {
      status = l.pinkaSlotStatusBlocked;
    } else {
      status =
          '${slot.displayName ?? l.pinkaAnonymous} · ${fmtEur(slot.priceCents)} €';
    }

    return _bottomBarShell(
      theme,
      cs,
      icon: free ? Icons.check_circle_outline : Icons.block,
      iconColor: free ? cs.tertiary : cs.onSurfaceVariant,
      status: status,
      coords: '$x:$y',
      buttonLabel:
          free ? l.pinkaSlotPickerConfirm(fmtEur(price)) : l.pinkaSlotPickerTaken,
      onPressed: free ? () => Navigator.of(context).pop('$x:$y') : null,
    );
  }

  Widget _bottomBarShell(
    ThemeData theme,
    ColorScheme cs, {
    required IconData icon,
    required Color iconColor,
    required String status,
    required String? coords,
    required String buttonLabel,
    required VoidCallback? onPressed,
  }) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(status,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis),
                ),
                if (coords != null)
                  Text('· $coords',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 4),
            Text(l.pinkaSlotPickerHint,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: cs.tertiary,
                foregroundColor: cs.onTertiary,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              icon: const Icon(Icons.check, size: 18),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kandidatska ćelija u TRANSFORMIRANOM prostoru grida (pomiče se s pan/zoom).
/// Debljina ruba proporcionalna ćeliji da bude vidljiva na svakom zoomu.
class _PickerCandidatePainter extends CustomPainter {
  final int width;
  final int height;

  /// `null` kad je nišan izvan mreže (iznad praznog platna) — ništa se ne crta.
  final int? cell;
  final Color color;

  _PickerCandidatePainter({
    required this.width,
    required this.height,
    required this.cell,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = cell;
    if (c == null) return;
    final cellW = size.width / width;
    final cellH = size.height / height;
    final x = c % width;
    final y = c ~/ width;
    final rect = Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH);
    final sw = math.max(cellW * 0.16, 1.5);
    // Tamni halo pa svijetli rub — čitljivo i na svijetlim i tamnim zonama.
    canvas.drawRect(
      rect.inflate(sw * 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw * 1.8
        ..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRect(
      rect.inflate(sw * 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_PickerCandidatePainter old) =>
      old.cell != cell || old.color != color;
}

/// Fiksni nišan na sredini ekrana (crosshair + središnja točka).
class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ReticlePainter());
}

class _ReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = Colors.black.withValues(alpha: 0.5)
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white
      ..strokeCap = StrokeCap.round;

    // Četiri kraka s prazninom u sredini + središnja točka.
    const gap = 7.0;
    const len = 16.0;
    void cross(Paint p) {
      canvas.drawLine(Offset(c.dx, c.dy - gap - len), Offset(c.dx, c.dy - gap), p);
      canvas.drawLine(Offset(c.dx, c.dy + gap), Offset(c.dx, c.dy + gap + len), p);
      canvas.drawLine(Offset(c.dx - gap - len, c.dy), Offset(c.dx - gap, c.dy), p);
      canvas.drawLine(Offset(c.dx + gap, c.dy), Offset(c.dx + gap + len, c.dy), p);
    }

    cross(halo);
    cross(line);
    canvas.drawCircle(c, 2.5, Paint()..color = Colors.black.withValues(alpha: 0.5));
    canvas.drawCircle(c, 1.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) => false;
}
