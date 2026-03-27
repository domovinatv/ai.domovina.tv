import 'package:flutter/material.dart';
import '../models/podcast_summary.dart';

class SummarySection extends StatelessWidget {
  final PodcastSummary summary;

  const SummarySection({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary.summary;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Abstract
          _SectionTitle(title: 'Sažetak'),
          const SizedBox(height: 8),
          Text(s.abstractHr, style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
          const SizedBox(height: 24),

          // Key Topics
          _SectionTitle(title: 'Ključne teme'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: s.keyTopics
                .map((t) => Chip(
                      label: Text(t, style: theme.textTheme.labelSmall),
                      side: BorderSide(color: theme.colorScheme.outline),
                      backgroundColor: Colors.transparent,
                      padding: EdgeInsets.zero,
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),

          // Speakers
          _SectionTitle(title: 'Govornici'),
          const SizedBox(height: 10),
          ...s.speakers.map((sp) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        sp.suggestedName.isNotEmpty
                            ? sp.suggestedName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sp.suggestedName,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                          sp.role,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 24),

          // Key Points
          _SectionTitle(title: 'Ključni zaključci'),
          const SizedBox(height: 10),
          ...s.keyPoints.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${e.key + 1}',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(e.value,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.5)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}
