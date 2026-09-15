/// Legenda tipki daljinskog na TV ekranima — „OK = sviraj/pauza",
/// „[◀][▶] = odlomci", „BACK = video".
///
/// **Rule (smjer se crta ikonom, ne znakom)**: do 15.9.2026. su smjerovi bili
/// znakovi `◀ ▶ ▲ ▼` upisani u sam lokalizirani string. Takav glif ovisi o
/// fontu koji ga na kraju dobije: dio platformi ga podigne u **emoji prikaz**
/// (šarena sličica usred sivog teksta), a font koji ga nema tiho nacrta
/// `.notdef` kvadratić — isti kvar koji je pogodio 65 759 OG slika (vidi
/// CLAUDE.md, „u OG sliku se ne piše emoji"). `Icons.*` je vektor iz fonta koji
/// putuje s aplikacijom, pa tog rizika nema, a usput prati boju i veličinu koju
/// mu zada [TextStyle] pozivnog mjesta.
///
/// **Rule (u ARB idu samo RIJEČI)**: string u prijevodu nosi isključivo radnju
/// („odlomci", „sections"). Tipka je dio **sklopa**, ne teksta — inače svaki
/// novi jezik iznova prepisuje glifove i prva greška u prijepisu je nevidljiva
/// dok je netko ne ugleda na televizoru.
library;

import 'package:flutter/material.dart';

/// Jedan segment legende: jedna ili više tipki, pa što rade.
///
/// [keys] prima `String` (natpis na tipki — „OK", „BACK", „F") ili `IconData`
/// (smjer na D-padu). Miješanje je dopušteno: `['BACK', 'F']`.
@immutable
class TvHintEntry {
  final List<Object> keys;
  final String action;

  const TvHintEntry(this.keys, this.action);
}

/// Vodoravna legenda tipki. Prelama se ([Wrap]) jer engleski prijevod zna biti
/// širi od hrvatskog, a TV footer nema horizontalni scroll.
class TvKeyHint extends StatelessWidget {
  final List<TvHintEntry> entries;
  final TextStyle? style;
  final double iconSize;

  const TvKeyHint({
    super.key,
    required this.entries,
    this.style,
    this.iconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = style ??
        theme.textTheme.labelMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final color = effective?.color ?? theme.colorScheme.onSurfaceVariant;

    return Wrap(
      spacing: 18,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final key in entry.keys) ...[
                if (key is IconData)
                  Icon(key, size: iconSize, color: color)
                else
                  Text('$key', style: effective),
                const SizedBox(width: 2),
              ],
              Text(' = ${entry.action}', style: effective),
            ],
          ),
      ],
    );
  }
}
