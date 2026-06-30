import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../services/cdn_config.dart';
import '../../services/locale_service.dart';
import '../../l10n/app_localizations.dart';

import '../../theme/typography.dart';
import 'home_feed.dart';

/// Editorial hero sekcija — split layout (slika lijevo, tekst desno) na desktop,
/// stack na mobile. Compact dimenzije — slika je 16:9 ograničena na 480px wide
/// pa hero nikad nije visok preko ~290px.
///
/// Desktop layout:
/// ```
/// ┌─────────────────┬───────────────────────────┐
/// │                 │  ISTAKNUTO                │
/// │  [thumb 16:9]   │  Naslov u serifu          │
/// │                 │  Channel · 2 dana · 1h    │
/// │                 │  [▶ Slušaj]  [♡ Spremi]   │
/// └─────────────────┴───────────────────────────┘
/// ```
///
/// Mobile layout:
/// ```
/// ┌────────────────────────┐
/// │  [thumb 16:9 full]     │
/// ├────────────────────────┤
/// │  ISTAKNUTO             │
/// │  Naslov...             │
/// │  [Slušaj] [Spremi]     │
/// └────────────────────────┘
/// ```
class HeroSection extends StatelessWidget {
  final FeaturedPick featured;
  final VoidCallback onPlay;
  final VoidCallback onSave;
  final bool isMobile;

  /// Vanjski razmak oko kartice. Default ostavlja zracni prostor ispod hero-a;
  /// [HeroCarousel] ga stisne jer kontrolnu traku (rotacija + dots) crta sam
  /// ispod kartice.
  final EdgeInsets outerPadding;

  const HeroSection({
    super.key,
    required this.featured,
    required this.onPlay,
    required this.onSave,
    required this.isMobile,
    this.outerPadding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: outerPadding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: theme.colorScheme.surfaceContainerLowest,
          child: InkWell(
            onTap: onPlay,
            child: isMobile ? _mobileLayout(theme) : _desktopLayout(theme),
          ),
        ),
      ),
    );
  }

  /// Desktop split — slika lijevo (constrained 480px), tekst desno.
  Widget _desktopLayout(ThemeData theme) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Slika lijevo — fixed 460px wide, 16:9
          SizedBox(
            width: 460,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _coverImage(),
                  if (featured.video.video.magisteriumScore != null)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _magisteriumPill(theme, light: true),
                    ),
                ],
              ),
            ),
          ),
          // Tekst desno
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: _content(theme, light: false),
            ),
          ),
        ],
      ),
    );
  }

  /// Mobile stack — slika gore, tekst ispod.
  Widget _mobileLayout(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _coverImage(),
              if (featured.video.video.magisteriumScore != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _magisteriumPill(theme, light: true),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: _content(theme, light: false),
        ),
      ],
    );
  }

  Widget _coverImage() {
    // CDN URL (ne `video.thumbnail` koji moze biti i.ytimg.com - CORS blok).
    return Image.network(
      CdnConfig.thumbnailUrl(featured.video.video.id),
      fit: BoxFit.cover,
      errorBuilder: (c, e, s) => _backdropFallback(Theme.of(c)),
    );
  }

  Widget _backdropFallback(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.croBlue,
            AppTheme.croBlue.withValues(alpha: 0.7),
          ],
        ),
      ),
    );
  }

  Widget _content(ThemeData theme, {required bool light}) {
    final video = featured.video.video;
    final channelName = featured.video.channelName;
    final textColor = light ? Colors.white : theme.colorScheme.onSurface;
    final subColor = light
        ? Colors.white.withValues(alpha: 0.85)
        : theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Eyebrow + "Zašto?" info gumb
        Row(
          children: [
            Container(width: 24, height: 2, color: theme.colorScheme.tertiary),
            const SizedBox(width: 10),
            Text(
              appStrings.homeHeroEyebrow.toUpperCase(),
              style: AppTypography.eyebrowStyle(theme.colorScheme)
                  .copyWith(color: subColor),
            ),
            const SizedBox(width: 8),
            _WhyButton(pick: featured, color: subColor),
          ],
        ),
        const SizedBox(height: 12),

        // Title
        Text(
          video.displayTitle,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: textColor,
            height: 1.15,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),

        // Meta line
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              channelName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (video.date != null)
              Text('·  ${_formatDate(video.date!)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: subColor)),
            if (video.durationDisplay != null)
              Text('·  ${video.durationDisplay}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: subColor)),
          ],
        ),
        const SizedBox(height: 16),

        // CTA buttons
        Row(
          children: [
            FilledButton.icon(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow, size: 20),
              label: Text(appStrings.homeHeroListen),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.croBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: AppTheme.brandRim(theme.brightness),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.bookmark_border, size: 18),
              label: Text(appStrings.commonSave),
              style: OutlinedButton.styleFrom(
                foregroundColor: textColor,
                side: BorderSide(
                  color: textColor.withValues(alpha: 0.4),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _magisteriumPill(ThemeData theme, {required bool light}) {
    final score = featured.video.video.magisteriumScore!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.church, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            '$score',
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      final days = DateTime.now().difference(d).inDays;
      if (days == 0) return appStrings.homeAgoToday;
      if (days == 1) return appStrings.homeAgoYesterday;
      if (days < 7) return appStrings.homeAgoDays(days);
      if (days < 30) return appStrings.homeAgoWeeks((days / 7).floor());
      if (days < 365) return appStrings.homeAgoMonths((days / 30).floor());
      return iso;
    } catch (_) {
      return iso;
    }
  }
}

/// Mali "Zasto?" gumb pored "ISTAKNUTO" eyebrow-a — otvara dialog s
/// objektivnim kriterijima zbog kojih je epizoda izabrana.
class _WhyButton extends StatelessWidget {
  final FeaturedPick pick;
  final Color color;

  const _WhyButton({required this.pick, required this.color});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showWhyDialog(context, pick),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.help_outline, size: 11, color: color),
              const SizedBox(width: 4),
              Text(
                AppLocalizations.of(context).homeHeroWhyButton.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                  letterSpacing: 1.0,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showWhyDialog(BuildContext context, FeaturedPick pick) {
  showDialog<void>(
    context: context,
    builder: (ctx) => _WhyDialog(pick: pick),
  );
}

class _WhyDialog extends StatelessWidget {
  final FeaturedPick pick;

  const _WhyDialog({required this.pick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      title: Row(
        children: [
          Container(width: 24, height: 2, color: theme.colorScheme.tertiary),
          const SizedBox(width: 10),
          Text(
            l.homeWhyDialogTitle.toUpperCase(),
            style: AppTypography.eyebrowStyle(theme.colorScheme),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _reasonHeadline(pick.reason),
              style: theme.textTheme.headlineSmall?.copyWith(height: 1.2),
            ),
            const SizedBox(height: 16),
            _factsTable(theme, pick),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.homeWhyAlgorithmHeading.toUpperCase(),
                    style: AppTypography.eyebrowStyle(theme.colorScheme),
                  ),
                  const SizedBox(height: 10),
                  _algorithmTiers(theme, pick.reason),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l.homeWhyDialogExplainer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.homeWhyGotIt),
        ),
      ],
    );
  }

  String _reasonHeadline(FeaturedReason reason) {
    switch (reason) {
      case FeaturedReason.hiQualityRecent:
        return appStrings.homeReasonHeadlineHiQualityRecent;
      case FeaturedReason.hiQuality:
        return appStrings.homeReasonHeadlineHiQuality;
      case FeaturedReason.anyMagisterium:
        return appStrings.homeReasonHeadlineAnyMagisterium;
      case FeaturedReason.newest:
        return appStrings.homeReasonHeadlineNewest;
    }
  }

  Widget _factsTable(ThemeData theme, FeaturedPick pick) {
    final l = appStrings;
    final rows = <(String, String)>[
      (l.homeWhyFactChannel, pick.video.channelName),
      if (pick.magisteriumScore != null)
        (l.homeWhyFactScore, '${pick.magisteriumScore} / 100'),
      if (pick.daysAgo != null)
        (l.homeWhyFactPublished, _daysAgoLabel(pick.daysAgo!)),
      (
        l.homeWhyFactAiProcessing,
        (pick.video.video.pipeline?.hasMagisterium ?? false)
            ? l.homeWhyFactAiYes
            : l.homeWhyFactAiNo
      ),
      if (pick.combinedScore != null)
        (
          l.homeWhyFactWeight,
          l.homeWhyFactWeightValue(pick.combinedScore!.toStringAsFixed(1))
        ),
      (l.homeWhyFactPool, l.homeWhyFactPoolValue(pick.candidatePool)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    r.$1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    r.$2,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _algorithmTiers(ThemeData theme, FeaturedReason activeTier) {
    final l = appStrings;
    final tiers = [
      (
        FeaturedReason.hiQualityRecent,
        l.homeTier1Title,
        l.homeTier1Desc,
      ),
      (
        FeaturedReason.hiQuality,
        l.homeTier2Title,
        l.homeTier2Desc,
      ),
      (
        FeaturedReason.anyMagisterium,
        l.homeTier3Title,
        l.homeTier3Desc,
      ),
      (
        FeaturedReason.newest,
        l.homeTier4Title,
        l.homeTier4Desc,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in tiers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                     color: t.$1 == activeTier
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.$2,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: t.$1 == activeTier
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: t.$1 == activeTier
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.$3,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _daysAgoLabel(int days) {
    if (days == 0) return appStrings.homeAgoToday;
    if (days == 1) return appStrings.homeAgoYesterday;
    if (days < 7) return appStrings.homeAgoDays(days);
    if (days < 30) return appStrings.homeAgoWeeks((days / 7).floor());
    if (days < 365) return appStrings.homeAgoMonths((days / 30).floor());
    return appStrings.homeAgoYears((days / 365).floor());
  }
}
