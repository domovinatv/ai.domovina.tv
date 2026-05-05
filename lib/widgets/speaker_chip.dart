import 'package:flutter/material.dart';

import '../models/podcast_summary.dart';

/// Kompaktni chip koji prikazuje govornika kao "Ime · Voditelj/Gost".
/// Ako pipeline nije izvukao pravo ime (suggested_name == role), prikazuje
/// samo capitalized roleLabel.
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

    return Chip(
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
  }
}
