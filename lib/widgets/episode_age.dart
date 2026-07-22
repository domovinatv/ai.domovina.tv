import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Parsiraj datum epizode (YYYY-MM-DD ili ISO). null ako ne ide.
DateTime? parseEpisodeDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}

/// Broj dana od epizode do danas (>= 0).
int episodeAgeDays(DateTime date, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(date).inDays;
  return d < 0 ? 0 : d;
}

/// Kratka relativna oznaka starosti (lokalizirana).
String episodeAgeLabel(int days, AppLocalizations s) {
  if (days <= 0) return s.sectionAgeToday;
  if (days == 1) return s.sectionAgeYesterday;
  if (days < 7) return s.sectionAgeDays(days);
  if (days < 31) {
    final w = (days / 7).floor();
    return s.sectionAgeWeeks(w);
  }
  if (days < 365) {
    final m = (days / 30).floor();
    return s.sectionAgeMonths(m);
  }
  final y = (days / 365).floor();
  return s.sectionAgeYears(y);
}

/// Boja po starosti: novije = zelena → svijetlozelena → jantar → narančasta →
/// crvena (staro).
Color episodeAgeColor(int days) {
  if (days <= 14) return const Color(0xFF2E7D32); // zelena
  if (days <= 60) return const Color(0xFF7CB342); // svijetlozelena
  if (days <= 180) return const Color(0xFFF9A825); // jantar
  if (days <= 365) return const Color(0xFFEF6C00); // narančasta
  return const Color(0xFFC62828); // crvena — staro
}

/// Mali badge: obojena točka + relativna oznaka starosti epizode. Boja
/// signalizira svježinu. Tooltip pokazuje točan datum. Ako datum ne postoji
/// ili se ne da parsirati, ne prikazuje ništa.
class EpisodeAgeChip extends StatelessWidget {
  final String? date;
  final TextStyle? style;

  const EpisodeAgeChip(this.date, {this.style, super.key});

  @override
  Widget build(BuildContext context) {
    final d = parseEpisodeDate(date);
    if (d == null) return const SizedBox.shrink();
    final days = episodeAgeDays(d);
    final color = episodeAgeColor(days);
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final base = style ?? theme.textTheme.labelSmall ?? const TextStyle();
    final exact =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}.';
    return Tooltip(
      message: l.sectionPublishedOn(exact),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            episodeAgeLabel(days, l),
            style: base.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
