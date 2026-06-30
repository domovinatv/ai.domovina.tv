import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Jasno labelirani gumb za prebacivanje izmedju detaljnog (`/v/`) i
/// jednostavnog (`/m/`) prikaza epizode. Zamjenjuje raniju golu `unfold`
/// ikonu koja korisnicima nije govorila sto radi.
///
/// Gumb nosi rijec ("Detaljno" / "Jednostavno") + ikonu, a puni opis sto
/// svaki nacin sadrzi je u tooltipu (hover na desktopu, long-press na mobu).
///
/// [toSimple] = true → gumb vodi na JEDNOSTAVNI prikaz (stoji na detaljnom
/// ekranu). false → vodi na DETALJNI prikaz (stoji na jednostavnom ekranu).
class ViewModeToggleButton extends StatelessWidget {
  final bool toSimple;
  final VoidCallback onPressed;

  const ViewModeToggleButton({
    super.key,
    required this.toSimple,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final label = toSimple ? l.mediaViewSimple : l.mediaViewDetailed;
    final icon = toSimple ? Icons.unfold_less : Icons.unfold_more;
    final tooltip =
        toSimple ? l.mediaViewSimpleTooltip : l.mediaViewDetailedTooltip;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Center(
        child: Tooltip(
          message: tooltip,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
              side: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
              ),
              textStyle: theme.textTheme.labelMedium,
            ),
          ),
        ),
      ),
    );
  }
}
