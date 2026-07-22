import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/episode_language.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// HR/EN pill prebacivač UI JEZIKA (home app bar, Zid podrške…).
/// Vidljiv svima, uključujući neautentificirane korisnike; odabir se sprema
/// lokalno (LocaleController, default hrvatski). MaterialApp sluša
/// LocaleController (vidi main.dart) pa se cijela aplikacija rebuilda na promjenu.
///
/// Pill toggle (ne dropdown) — dropdown ima smisla tek s ≥3 jezika; dok su
/// samo HR/EN, jedan tap je brži. Vizualno prati LanguageToggleChip
/// (per-epizoda jezik SADRŽAJA), ali ovo je jezik chrome-a — odvojen koncept.
///
/// Sprega je dvosmjerna: uz UI jezik sprema se i preferirani jezik SADRŽAJA
/// (sticky pref za buduće epizode) — korisnik koji prebaci sučelje na EN
/// očekuje i engleske članke gdje prijevod postoji, i obratno. Isto radi
/// LanguageToggleChip u suprotnom smjeru (sadržaj → UI).
class LanguageToggleButton extends StatelessWidget {
  const LanguageToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: LocaleController.instance,
      builder: (context, _) {
        final isEnglish = LocaleController.instance.isEnglish;
        final l = AppLocalizations.of(context);
        return Semantics(
          container: true,
          label: l.authSectionLanguage,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withAlpha(120),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Segment(
                  label: 'HR',
                  isSelected: !isEnglish,
                  semanticLabel: 'Hrvatski',
                  onTap: () {
                    LocaleController.instance.setLocale(const Locale('hr'));
                    savePreferredLanguage(EpisodeLanguage.hr);
                  },
                ),
                _Segment(
                  label: 'EN',
                  isSelected: isEnglish,
                  semanticLabel: 'English',
                  onTap: () {
                    LocaleController.instance.setLocale(const Locale('en'));
                    savePreferredLanguage(EpisodeLanguage.en);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool isSelected;
  final String semanticLabel;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.isSelected,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isSelected ? AppTheme.croBlue : Colors.transparent;
    final fg =
        isSelected ? Colors.white : theme.colorScheme.onSurface.withAlpha(160);

    return Semantics(
      selected: isSelected,
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.fromBorderSide(
                isSelected
                    ? AppTheme.brandRim(theme.brightness)
                    : BorderSide.none,
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
