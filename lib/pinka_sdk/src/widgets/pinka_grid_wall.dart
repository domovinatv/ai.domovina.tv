library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../main.dart' show log;
import '../../../../theme/app_theme.dart';
import '../models/pinka_public_contribution.dart';
import '../util/pinka_money.dart';
import 'pinka_common.dart';

/// Vizualni "zid" od 120×120 kvadratića: donacijom kupuješ svoj kvadratić.
/// 10 koncentričnih cjenovnih prstenova (rub 1 € → jezgra 1000 €), portirano
/// iz pixel-grid-v1 billboard buildera. Crta se kao JEDAN CustomPaint pass
/// (nikad 14.400 widgeta); hover/selekcija idu kroz zaseban overlay painter
/// iza RepaintBoundaryja da ne repaintaju bazu.
///
/// Faza 1 = prezentacija: doprinosi se na ćelije mapiraju deterministički na
/// klijentu (hash id-a unutar najskupljeg prstena koji iznos pokriva).
/// TODO: prava rezervacija kvadratića traži `cell_x`/`cell_y` kolone u
/// `contributions` + unique constraint — backend faza 2 u domovina-api.
class PinkaGridWall extends StatefulWidget {
  final List<PinkaPublicContribution> contributions;

  /// Tap na SLOBODAN kvadratić — host postavi iznos u panel za uplatu.
  final void Function(int amountCents, String zoneName)? onZoneTap;

  const PinkaGridWall({
    super.key,
    required this.contributions,
    this.onZoneTap,
  });

  @override
  State<PinkaGridWall> createState() => _PinkaGridWallState();
}

const int _gridSide = 120;

/// Prsten zida: [startLayer] = udaljenost od ruba od koje prsten počinje,
/// [priceCents] = cijena kvadratića. Poredano izvana (0) prema jezgri (9);
/// geometrija identična pixel-grid-v1 `_zones`, cijene ÷10 pa vanjskih pet
/// prstenova odgovara preset čipovima u PinkaContributePanel.
class _ZoneConfig {
  final int startLayer;
  final int priceCents;

  const _ZoneConfig(this.startLayer, this.priceCents);
}

const List<_ZoneConfig> _zones = [
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

/// Prsten ćelije preko udaljenosti od ruba — ekvivalent "first match wins"
/// containsPoint skeniranju iz originala, ali O(1) jer su prstenovi koncentrični.
int _zoneIndexOf(int x, int y) {
  final layer = [x, y, _gridSide - 1 - x, _gridSide - 1 - y]
      .reduce((a, b) => a < b ? a : b);
  for (var i = _zones.length - 1; i >= 0; i--) {
    if (layer >= _zones[i].startLayer) return i;
  }
  return 0;
}

/// Ćelije po prstenu (indeks = y*120+x, row-major) — strukturno, keširano
/// jednom za cijelu aplikaciju.
final Map<int, List<int>> _zoneCellsCache = {};

List<int> _zoneCells(int zone) {
  return _zoneCellsCache.putIfAbsent(zone, () {
    final cells = <int>[];
    for (var y = 0; y < _gridSide; y++) {
      for (var x = 0; x < _gridSide; x++) {
        if (_zoneIndexOf(x, y) == zone) cells.add(y * _gridSide + x);
      }
    }
    return cells;
  });
}

/// FNV-1a 32-bit — stabilan hash id-a doprinosa za deterministički placement
/// (bez Random/DateTime: isti popis doprinosa uvijek daje isti raspored).
int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final cu in s.codeUnits) {
    h ^= cu;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

class _PinkaGridWallState extends State<PinkaGridWall> {
  /// Ćelija (y*120+x) → doprinos koji je "drži".
  Map<int, PinkaPublicContribution> _cellOwners = const {};

  /// Potpis zadnjeg mapiranog popisa — preskoči replacement kad se zid nije
  /// promijenio (refresh svakih 12 s obično vrati isti popis).
  String _placedSignature = '';

  int? _hoverCell;
  int? _selectedCell;

  @override
  void initState() {
    super.initState();
    _placeContributions();
  }

  @override
  void didUpdateWidget(covariant PinkaGridWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    _placeContributions();
  }

  void _placeContributions() {
    final sig = widget.contributions.map((c) => c.id).join(',');
    if (sig == _placedSignature) return;
    _placedSignature = sig;

    // Kanonski redoslijed po id-u — placement ne ovisi o redoslijedu s API-ja.
    final sorted = [...widget.contributions]
      ..sort((a, b) => a.id.compareTo(b.id));
    final owners = <int, PinkaPublicContribution>{};
    var spills = 0;
    var unplaced = 0;
    for (final c in sorted) {
      // Najskuplji prsten koji si iznos može priuštiti; ispod 1 € → rub.
      var zone = 0;
      for (var i = _zones.length - 1; i >= 0; i--) {
        if (c.amountCents >= _zones[i].priceCents) {
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
    log('PinkaGridWall: mapirano ${owners.length}/${widget.contributions.length}'
        ' doprinosa${spills > 0 ? ', $spills prelijevanja u jeftiniji prsten' : ''}'
        '${unplaced > 0 ? ', $unplaced NEsmješteno (zid pun)' : ''}');
  }

  List<String> _zoneNames(AppLocalizations l) => [
        l.pinkaGridZoneOuterBelt,
        l.pinkaGridZoneDefenseRing,
        l.pinkaGridZoneMidBelt,
        l.pinkaGridZoneHighZone,
        l.pinkaGridZoneGoldenCircle,
        l.pinkaGridZoneBusiness,
        l.pinkaGridZoneExecutive,
        l.pinkaGridZonePrestige,
        l.pinkaGridZoneElite,
        // Jezgra se verzalizira u kodu (ARB vrijednosti bez ALL-CAPS-a).
        l.pinkaGridZoneCore.toUpperCase(),
      ];

  int? _cellAt(Offset local, Size size) {
    final cellW = size.width / _gridSide;
    final cellH = size.height / _gridSide;
    if (cellW <= 0 || cellH <= 0) return null;
    final x = (local.dx / cellW).floor().clamp(0, _gridSide - 1);
    final y = (local.dy / cellH).floor().clamp(0, _gridSide - 1);
    return y * _gridSide + x;
  }

  void _setHover(int? cell) {
    if (cell == _hoverCell) return; // setState samo na promjenu ćelije
    setState(() => _hoverCell = cell);
  }

  void _onTap(int? cell) {
    if (cell == null) return;
    final owner = _cellOwners[cell];
    if (owner != null) {
      _showOwnerSheet(owner);
      return;
    }
    final zone = _zoneIndexOf(cell % _gridSide, cell ~/ _gridSide);
    setState(() => _selectedCell = cell);
    final name = _zoneNames(AppLocalizations.of(context))[zone];
    widget.onZoneTap?.call(_zones[zone].priceCents, name);
  }

  /// Bottom sheet za zauzeti kvadratić — isti vizualni jezik kao kartica na
  /// PinkaWallList zidu (ime + iznos + poruka).
  void _showOwnerSheet(PinkaPublicContribution c) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.pinkaGridTakenTitle,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.displayNameOrAnon,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${fmtEur(c.amountCents)} €',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
                if (c.message != null && c.message!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  PinkaLinkify(
                    text: c.message!.trim(),
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

    // Zone gradiraju kroz tint brand navy palete (croBlue → svjetlije prema
    // jezgri) — nikad cs.primary za brand-FILL (M3 dark ga izblijedi) i bez
    // random Material boja. Zauzete ćelije = tertiary (crveni akcent).
    final zoneColors = List<Color>.generate(
      _zones.length,
      (i) => Color.lerp(AppTheme.croBlue, Colors.white, 0.38 * i / 9)!,
    );
    final rim = AppTheme.brandRim(theme.brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.pinkaGridIntro,
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
            // Grid je 120×120 → kvadrat 1:1 (NE 16:9 billboard iz originala).
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                return MouseRegion(
                  onEnter: (e) => _setHover(_cellAt(e.localPosition, size)),
                  onHover: (e) => _setHover(_cellAt(e.localPosition, size)),
                  onExit: (_) => _setHover(null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onTap(_cellAt(d.localPosition, size)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Baza (14.400 ćelija) iza RepaintBoundaryja —
                        // repainta se samo kad se promijene doprinosi/tema,
                        // NE na hover.
                        RepaintBoundary(
                          child: CustomPaint(
                            isComplex: true,
                            painter: _GridPainter(
                              zoneColors: zoneColors,
                              occupiedColor: cs.tertiary,
                              occupiedCells: _cellOwners.keys.toSet(),
                              signature: _placedSignature,
                            ),
                          ),
                        ),
                        CustomPaint(
                          painter: _OverlayPainter(
                            hoverCell: _hoverCell,
                            selectedCell: _selectedCell,
                            color: theme.brightness == Brightness.dark
                                ? Colors.white
                                : AppTheme.croBlue,
                          ),
                        ),
                      ],
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

  /// Redak ispod grida: hover → zona/donator, inače uputa za tap.
  Widget _statusLabel(ThemeData theme, AppLocalizations l) {
    final style = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final cell = _hoverCell;
    if (cell == null) {
      return Text(l.pinkaGridTapHint,
          style: style, overflow: TextOverflow.ellipsis);
    }
    final owner = _cellOwners[cell];
    if (owner != null) {
      return Text(
        '${owner.displayNameOrAnon} · ${fmtEur(owner.amountCents)} €',
        style: style?.copyWith(
            color: theme.colorScheme.tertiary, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      );
    }
    final zone = _zoneIndexOf(cell % _gridSide, cell ~/ _gridSide);
    return Text(
      l.pinkaGridZonePriceLabel(
          _zoneNames(l)[zone], fmtEur(_zones[zone].priceCents)),
      style: style?.copyWith(fontWeight: FontWeight.w600),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Baza zida: svih 14.400 ćelija u jednom paint passu (port BillboardPainter).
class _GridPainter extends CustomPainter {
  final List<Color> zoneColors;
  final Color occupiedColor;
  final Set<int> occupiedCells;

  /// Potpis placement mape — jeftina usporedba u [shouldRepaint].
  final String signature;

  _GridPainter({
    required this.zoneColors,
    required this.occupiedColor,
    required this.occupiedCells,
    required this.signature,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / _gridSide;
    final cellH = size.height / _gridSide;
    const spacing = 0.5;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var y = 0; y < _gridSide; y++) {
      for (var x = 0; x < _gridSide; x++) {
        final cell = y * _gridSide + x;
        paint.color = occupiedCells.contains(cell)
            ? occupiedColor
            : zoneColors[_zoneIndexOf(x, y)];
        canvas.drawRect(
          Rect.fromLTWH(
            x * cellW + spacing,
            y * cellH + spacing,
            cellW - spacing * 2,
            cellH - spacing * 2,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    return oldDelegate.signature != signature ||
        oldDelegate.occupiedColor != occupiedColor ||
        oldDelegate.zoneColors.first != zoneColors.first ||
        oldDelegate.zoneColors.last != zoneColors.last;
  }
}

/// Overlay iznad baze: samo hover + zadnje tapnuta ćelija (2 strokea max) —
/// repainta se na svaki pomak ćelije, ali NE dira bazni pass.
class _OverlayPainter extends CustomPainter {
  final int? hoverCell;
  final int? selectedCell;
  final Color color;

  _OverlayPainter({
    required this.hoverCell,
    required this.selectedCell,
    required this.color,
  });

  Rect _cellRect(int cell, Size size) {
    final cellW = size.width / _gridSide;
    final cellH = size.height / _gridSide;
    final x = cell % _gridSide;
    final y = cell ~/ _gridSide;
    return Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (selectedCell != null) {
      canvas.drawRect(
        _cellRect(selectedCell!, size).inflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
    }
    if (hoverCell != null && hoverCell != selectedCell) {
      canvas.drawRect(
        _cellRect(hoverCell!, size),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter oldDelegate) {
    return oldDelegate.hoverCell != hoverCell ||
        oldDelegate.selectedCell != selectedCell ||
        oldDelegate.color != color;
  }
}
