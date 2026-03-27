import 'package:flutter/material.dart';
import '../models/podcast_summary.dart';

class EntitiesSection extends StatelessWidget {
  final SummaryContent summary;

  const EntitiesSection({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EntityGroup(
            icon: Icons.person_outline,
            title: 'Osobe',
            items: summary.mentionedPeople,
            color: Colors.blue,
          ),
          const SizedBox(height: 16),
          _EntityGroup(
            icon: Icons.place_outlined,
            title: 'Mjesta',
            items: summary.mentionedPlaces,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          _EntityGroup(
            icon: Icons.business_outlined,
            title: 'Organizacije',
            items: summary.mentionedOrganizations,
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

  const _EntityGroup({
    required this.icon,
    required this.title,
    required this.items,
    required this.color,
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
          children: items
              .map((item) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withAlpha(60)),
                    ),
                    child: Text(
                      item,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: color.withAlpha(220)),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
