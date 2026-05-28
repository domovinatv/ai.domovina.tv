import 'package:flutter/material.dart';

import '../services/episode_language.dart';

/// Pill toggle HR ↔ EN za per-episode jezik prikaza tekstualnog sadrzaja.
///
/// Audio uvijek ostaje hrvatski. Renderiraj samo kad za epizodu postoji EN
/// prijevod na CDN-u (caller provjerava `EpisodeData.hasTranslationEn`).
class LanguageToggleChip extends StatelessWidget {
  final EpisodeLanguage current;
  final ValueChanged<EpisodeLanguage> onChanged;

  /// Kompaktna varijanta (manji padding/font) za AppBar action slot.
  final bool compact;

  const LanguageToggleChip({
    super.key,
    required this.current,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      label: 'Odabir jezika prikaza',
      child: Tooltip(
        message: current == EpisodeLanguage.en
            ? 'Translation provided literally, without AI hallucinations'
            : 'Prijevod je literarno doslovan, bez AI halucinacija',
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
                isSelected: current == EpisodeLanguage.hr,
                semanticLabel: 'Prebaci na hrvatski',
                compact: compact,
                onTap: () {
                  if (current != EpisodeLanguage.hr) {
                    onChanged(EpisodeLanguage.hr);
                  }
                },
              ),
              _Segment(
                label: 'EN',
                isSelected: current == EpisodeLanguage.en,
                semanticLabel: 'Switch to English',
                compact: compact,
                onTap: () {
                  if (current != EpisodeLanguage.en) {
                    onChanged(EpisodeLanguage.en);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool isSelected;
  final String semanticLabel;
  final bool compact;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.isSelected,
    required this.semanticLabel,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isSelected ? theme.colorScheme.primary : Colors.transparent;
    final fg = isSelected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface.withAlpha(160);

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
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              label,
              style: (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
                  ?.copyWith(
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
