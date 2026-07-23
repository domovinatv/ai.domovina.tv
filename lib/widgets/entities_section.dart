import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/person_hub.dart';
import '../models/podcast_summary.dart';
import '../services/episode_language.dart';
import '../l10n/app_localizations.dart';

class EntitiesSection extends StatelessWidget {
  final SummaryContent summary;

  /// Person-highlight (dolazak s /p/ profila preko `?p=<slug>`): chip osobe
  /// čiji slug matcha renderira se bijelo-na-crveno (needle dekoracija).
  final String? highlightPersonSlug;

  const EntitiesSection({
    super.key,
    required this.summary,
    this.highlightPersonSlug,
  });

  @override
  Widget build(BuildContext context) {
    final lang = EpisodeLanguageScope.of(context);
    final l = AppLocalizations.of(context);
    final people =
        pickLangList(lang, summary.mentionedPeople, summary.mentionedPeopleEn);
    final places =
        pickLangList(lang, summary.mentionedPlaces, summary.mentionedPlacesEn);
    final orgs = pickLangList(
        lang, summary.mentionedOrganizations, summary.mentionedOrganizationsEn);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EntityGroup(
            icon: Icons.person_outline,
            title: l.sectionPeople,
            items: people,
            color: Colors.blue,
            // Osobe vode na javni profil govornika (/p/:slug). Oni koji su i
            // govornici dobiju bogat profil; ostali (samo spomenuti) padnu na
            // uredno prazno stanje. Mjesta/organizacije nisu klikabilni.
            onItemTap: (name) => context.go('/p/${personSlug(name)}'),
            isHighlighted: highlightPersonSlug != null
                ? (name) => personSlug(name) == highlightPersonSlug
                : null,
          ),
          const SizedBox(height: 16),
          _EntityGroup(
            icon: Icons.place_outlined,
            title: l.sectionPlaces,
            items: places,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          _EntityGroup(
            icon: Icons.business_outlined,
            title: l.sectionOrganizations,
            items: orgs,
            color: Colors.orange,
          ),
        ],
      ),
    );
  }
}

class _EntityGroup extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;
  final Color color;

  /// Ako je zadan, svaki chip postaje klikabilan (npr. osobe → profil).
  final void Function(String item)? onItemTap;

  /// Ako je zadan i vrati true, chip se renderira bijelo-na-crveno
  /// (person-needle highlight).
  final bool Function(String item)? isHighlighted;

  const _EntityGroup({
    required this.icon,
    required this.title,
    required this.items,
    required this.color,
    this.onItemTap,
    this.isHighlighted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 6),
            Text(
              '(${items.length})',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items.map((item) {
            final highlighted = isHighlighted?.call(item) ?? false;
            final chip = Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: highlighted
                    ? theme.colorScheme.tertiary
                    : color.withAlpha(20),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: highlighted
                      ? theme.colorScheme.tertiary
                      : color.withAlpha(60),
                ),
              ),
              child: Text(
                item,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: highlighted ? Colors.white : color.withAlpha(220),
                  fontWeight: highlighted ? FontWeight.bold : null,
                ),
              ),
            );
            if (onItemTap == null) return chip;
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onItemTap!(item),
              child: chip,
            );
          }).toList(),
        ),
      ],
    );
  }
}
