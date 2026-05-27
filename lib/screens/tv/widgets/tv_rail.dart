import 'package:flutter/material.dart';

/// Horizontalni rail s eyebrow naslovom — standardni TV pattern (Netflix,
/// YouTube, Apple TV). D-pad LEFT/RIGHT scrolla kroz [cards], a fokus
/// ensureVisible (vidi tv_focus.dart) drzi aktivnu karticu u centru viewporta.
///
/// [height] mora biti dovoljan za karticu + bottom text — episode card ~240,
/// channel card ~260 zbog kvadratnog avatara.
class TvRail extends StatelessWidget {
  final String eyebrow;
  final List<Widget> cards;
  final double height;
  final double cardSpacing;
  final EdgeInsetsGeometry horizontalPadding;

  const TvRail({
    super.key,
    required this.eyebrow,
    required this.cards,
    required this.height,
    this.cardSpacing = 20,
    this.horizontalPadding = const EdgeInsets.symmetric(horizontal: 48),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: horizontalPadding,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 3,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                eyebrow.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: horizontalPadding is EdgeInsets
                ? horizontalPadding as EdgeInsets
                : const EdgeInsets.symmetric(horizontal: 48),
            itemCount: cards.length,
            separatorBuilder: (_, _) => SizedBox(width: cardSpacing),
            itemBuilder: (context, i) => cards[i],
          ),
        ),
      ],
    );
  }
}
