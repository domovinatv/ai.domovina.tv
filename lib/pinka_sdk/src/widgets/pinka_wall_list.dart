library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../models/pinka_link_preview.dart';
import '../models/pinka_public_contribution.dart';
import '../util/pinka_money.dart';
import 'pinka_common.dart';

/// "Zid podrške" — lista javnih doprinosa. Novi unosi (u [flashIds]) dobiju
/// kratku fade/slide "arrive" animaciju. Bez vlastitog scrolla (host scrolla).
class PinkaWallList extends StatelessWidget {
  final List<PinkaPublicContribution> contributions;
  final Set<String> flashIds;

  const PinkaWallList({
    super.key,
    required this.contributions,
    this.flashIds = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in contributions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _WallEntry(contribution: c, flash: flashIds.contains(c.id)),
          ),
      ],
    );
  }
}

class _WallEntry extends StatelessWidget {
  final PinkaPublicContribution contribution;
  final bool flash;

  const _WallEntry({required this.contribution, required this.flash});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = contribution;
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: flash
            ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: flash
              ? theme.colorScheme.tertiary.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.displayNameOrAnon,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${fmtEur(c.amountCents)} €',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ),
          if (c.message != null && c.message!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            PinkaLinkify(
              text: c.message!.trim(),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (c.linkPreview != null && c.linkPreview!.hasContent) ...[
            const SizedBox(height: 8),
            _LinkPreviewCard(preview: c.linkPreview!),
          ],
        ],
      ),
    );

    if (!flash) return card;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
      ),
      child: card,
    );
  }
}

class _LinkPreviewCard extends StatelessWidget {
  final PinkaLinkPreview preview;

  const _LinkPreviewCard({required this.preview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final p = preview;
    return InkWell(
      onTap: () => pinkaLaunch(p.url),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.siteName ?? l.pinkaLink} ↗',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            if (p.title?.isNotEmpty ?? false) ...[
              const SizedBox(height: 2),
              Text(
                p.title!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
            if (p.description?.isNotEmpty ?? false) ...[
              const SizedBox(height: 2),
              Text(
                p.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
