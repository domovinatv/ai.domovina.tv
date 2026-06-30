import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/magisterium_data.dart';
import '../services/episode_language.dart';
import '../services/locale_service.dart';

/// Overall Magisterium score card with iteration breakdown.
class MagisteriumSection extends StatelessWidget {
  final MagisteriumData magisterium;

  const MagisteriumSection({super.key, required this.magisterium});

  static Color scoreColor(int? score) {
    if (score == null) return Colors.grey;
    if (score >= 90) return const Color(0xFF2E7D32); // deep green
    if (score >= 70) return const Color(0xFF558B2F); // light green
    if (score >= 50) return const Color(0xFFF9A825); // amber
    if (score >= 30) return const Color(0xFFEF6C00); // orange
    return const Color(0xFFC62828); // red
  }

  static String scoreLabel(int? score) {
    if (score == null) return 'N/A';
    if (score >= 90) return appStrings.magisteriumScoreActivelyPromotes;
    if (score >= 70) return appStrings.magisteriumScoreMostlyAligned;
    if (score >= 50) return appStrings.magisteriumScorePartiallyAligned;
    if (score >= 30) return appStrings.magisteriumScoreDeviates;
    return appStrings.magisteriumScoreContradicts;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final score = magisterium.overallScore;
    final color = scoreColor(score);
    final lang = EpisodeLanguageScope.of(context);
    final interpretation = pickLang(
      lang,
      magisterium.scoreInterpretation ?? scoreLabel(score),
      magisterium.scoreInterpretationEn,
    );
    final subtitleText = l.magisteriumAlignmentSubtitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.church, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                'Magisterium AI',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Overall score card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Row(
              children: [
                // Score circle
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withAlpha(30),
                    border: Border.all(color: color, width: 3),
                  ),
                  child: Center(
                    child: Text(
                      score != null ? '$score' : '?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        interpretation,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitleText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (magisterium.totalConcerns > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          l.magisteriumTheologicalConcerns(
                              magisterium.totalConcerns),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFEF6C00),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Iteration breakdown
          if (magisterium.scoreBreakdown.length > 1) ...[
            const SizedBox(height: 12),
            ...magisterium.scoreBreakdown.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.croBlue,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.fromBorderSide(
                            AppTheme.brandRim(theme.brightness),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${b.iteration}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pickLang(lang, b.theme, b.themeEn),
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scoreColor(b.score).withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: scoreColor(b.score).withAlpha(80)),
                        ),
                        child: Text(
                          b.score != null ? '${b.score}' : '?',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: scoreColor(b.score),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
