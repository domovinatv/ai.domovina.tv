import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../models/channel_index.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/typography.dart';
import '../../widgets/magisterium_section.dart';
import '../../widgets/share_context_menu.dart';
import '../../widgets/cached_thumbnail.dart';

/// Editorial channel kartica s **dva layouta** ovisno o dimenzijama cover-a.
///
/// Kanali imaju ili banner cover (1060x175 ~6:1, 25/39 kanala) ili square
/// (900x900) / nemaju cover (14/39). Forsiranje uniform 16:9 daje ili stretch
/// (banner→16:9 izgleda razvučeno) ili wasted space (square u 16:9 boxu).
/// Zato `channel.hasBannerCover` getter selektira layout.
///
/// BANNER layout (cover w!=h):
/// ```
/// ┌──────────────────────────────┐
/// │  [banner cover @ native AR]  │
/// ├──────────────────────────────┤
/// │ [avatar]  Naziv kanala       │
/// │           KANAL · 12 EP · 8H │
/// │           ✝ 87  Aktivno      │
/// └──────────────────────────────┘
/// ```
///
/// SQUARE layout (cover w==h ili nema):
/// ```
/// ┌──────────────────────────────┐
/// │ [avatar]  Naziv kanala       │
/// │  (152px) KANAL · 12 EP · 8H  │
/// │           ✝ 87  Aktivno      │
/// └──────────────────────────────┘
/// ```
class ChannelCard extends StatefulWidget {
  final ChannelSummary channel;
  final VoidCallback onTap;

  const ChannelCard({
    super.key,
    required this.channel,
    required this.onTap,
  });

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  bool _hovering = false;

  /// Javna poveznica na kanal — `/c/<slug>` (slug koristi `-`, ne `_`).
  String get _shareUrl {
    final slug = widget.channel.id.replaceAll('_', '-');
    return 'https://domovina.ai/c/$slug';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final c = widget.channel;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: ShareContextMenu(
        url: _shareUrl,
        child: AnimatedScale(
        scale: _hovering ? 1.015 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: _hovering
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Material(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: c.hasBannerCover
                  ? _bannerLayout(theme, l)
                  : _squareLayout(theme, l),
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// BANNER layout — cover at native AR na vrhu, avatar + tekst ispod.
  Widget _bannerLayout(ThemeData theme, AppLocalizations l) {
    final c = widget.channel;
    final dim = c.avatarCoverDimensions!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: dim.aspectRatio,
          child: CachedThumbnail(
            url: c.avatarCover!,
            fit: BoxFit.cover,
            errorFallbackBuilder: (_) => _coverFallback(theme),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _squareAvatar(theme, size: 56, radius: 10),
              const SizedBox(width: 12),
              Expanded(child: _info(theme, l, includeAvatar: false)),
            ],
          ),
        ),
      ],
    );
  }

  /// SQUARE layout — veliki avatar lijevo (152px), tekst desno.
  Widget _squareLayout(ThemeData theme, AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _squareAvatar(theme, size: 132, radius: 12),
          const SizedBox(width: 14),
          Expanded(child: _info(theme, l, includeAvatar: false)),
        ],
      ),
    );
  }

  Widget _squareAvatar(ThemeData theme,
      {required double size, required double radius}) {
    final c = widget.channel;
    if (c.avatarSquare == null) return _avatarPlaceholder(theme, size, radius);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      // Avatari kanala NISU `thumbnail.png` pa nemaju WebP varijante; dobitak
      // je disk cache + `memCacheWidth`, koji spriječi dekodiranje originala
      // u punoj rezoluciji za kvadratić od `size` dp. (Najveći avatar u
      // registru je 5,8 MB — mjereno 25.8.2026.)
      child: CachedThumbnail(
        url: c.avatarSquare!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorFallbackBuilder: (_) => _avatarPlaceholder(theme, size, radius),
      ),
    );
  }

  Widget _avatarPlaceholder(ThemeData theme, double size, double radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.croBlue,
            AppTheme.croBlue.withValues(alpha: 0.75),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.podcasts,
          size: size * 0.4, color: Colors.white.withValues(alpha: 0.9)),
    );
  }

  Widget _coverFallback(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.croBlue,
            AppTheme.croBlue.withValues(alpha: 0.75),
          ],
        ),
      ),
    );
  }

  Widget _info(ThemeData theme, AppLocalizations l,
      {bool includeAvatar = false}) {
    final c = widget.channel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.homeChannelCardMeta(c.videoCount, c.durationDisplay).toUpperCase(),
          style: AppTypography.eyebrowStyle(theme.colorScheme),
        ),
        const SizedBox(height: 6),
        Text(
          c.name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontFamily: 'Playfair Display',
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (c.avgMagisteriumScore != null) ...[
          const SizedBox(height: 10),
          _magisteriumPill(theme, l, c.avgMagisteriumScore!),
        ],
      ],
    );
  }

  Widget _magisteriumPill(ThemeData theme, AppLocalizations l, int score) {
    final color = MagisteriumSection.scoreColor(score);
    final label = MagisteriumSection.scoreLabel(score, l);
    return Tooltip(
      message: l.homeChannelMagisteriumTooltip(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.church, size: 12, color: color),
            const SizedBox(width: 5),
            Text(
              '$score',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
