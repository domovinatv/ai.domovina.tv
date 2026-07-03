import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/person_hub.dart';
import '../models/podcast_summary.dart';

/// Kompaktni chip koji prikazuje govornika kao "Ime · Voditelj/Gost".
/// Ako pipeline nije izvukao pravo ime (suggested_name == role), prikazuje
/// samo capitalized roleLabel.
///
/// Kad govornik ima PRAVO ime (displayName != null), chip je tappable i vodi
/// na javni profil govornika `/p/:slug`. Role-labeli bez imena ("Voditelj",
/// "Gost") NISU u bazi pa se ne linkaju.
class SpeakerChip extends StatelessWidget {
  final SummarySpeaker speaker;

  const SpeakerChip({super.key, required this.speaker});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = speaker.displayName;
    final roleLabel = speaker.roleLabel;

    final label = name != null
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (roleLabel.isNotEmpty)
                  TextSpan(
                    text: '  ·  $roleLabel',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          )
        : Text(
            roleLabel.isNotEmpty ? roleLabel : '—',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          );

    final chip = Chip(
      avatar: Icon(
        Icons.person,
        size: 16,
        color: theme.colorScheme.onSecondaryContainer,
      ),
      label: label,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );

    // Samo govornici s pravim imenom vode na profil (/p/:slug). Bez imena
    // (role-label) → nema linka jer takav slug ne postoji u bazi.
    if (name == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.go('/p/${personSlug(name)}'),
      child: chip,
    );
  }
}
