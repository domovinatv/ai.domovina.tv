import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/person_hub.dart';
import '../../theme/typography.dart';
import '../../widgets/magisterium_section.dart';
import '../../widgets/person_monogram.dart';
import '../../widgets/share_context_menu.dart';

/// Kartica osobe kao **virtualnog kanala** — katalog (`/channels`) i sve
/// površine gdje osoba stoji uz kanale.
///
/// Namjerno je ZASEBAN fajl, a ne grana u `channel_card.dart`: osoba nema
/// `ChannelSummary` ugovor (nema `UC…` id, nema cover, nema `hasBannerCover`),
/// a kartica kanala je dijeljena s home-om i TV-om pa svaka njezina izmjena
/// nosi rizik van ovog featurea (odluka T4 u `docs/plans/virtualni-kanali.md`).
///
/// Layout je namjerno IDENTIČAN SQUARE layoutu kartice kanala (avatar 132 px
/// lijevo, tekst desno) — osoba se mora čitati kao ravnopravan kanal. Razlika
/// je tiha i jedna: eyebrow kaže „OSOBA · 17 EP · 13H 39M" umjesto „KANAL · …"
/// (odluka O9), a podnaslov izrijekom kaže da je riječ o gostovanjima na tuđim
/// kanalima — kartica nikad ne tvrdi „službeni kanal osobe" (granica u O8).
///
/// ```
/// ┌──────────────────────────────┐
/// │ [monogram] OSOBA · 17 EP · … │
/// │  (132px)   Marijana Š. Robić │
/// │            Gostuje u 17 …    │
/// └──────────────────────────────┘
/// ```
class PersonCard extends StatefulWidget {
  final PersonSummary person;
  final VoidCallback onTap;

  const PersonCard({
    super.key,
    required this.person,
    required this.onTap,
  });

  /// „Gostuje u 17 epizoda na 17 kanala, 2020.–2026." — isti deterministički
  /// podnaslov kao hero na `/p/:slug`. Godine idu kao String placeholderi (int
  /// bi kroz `NumberFormat` postao „2.026"). `null` kad agregat nije potpun
  /// (stari backend bez godina) — tada kartica jednostavno nema podnaslov.
  static String? subtitleOf(AppLocalizations l, PersonSummary p) {
    if (p.episodeCount == 0 || p.channelCount == 0) return null;
    final from = p.firstYear ?? p.lastYear;
    final to = p.lastYear ?? p.firstYear;
    if (from == null || to == null) return null;
    if (from == to) {
      return l.personVirtualChannelSubtitleOneYear(
          p.episodeCount, p.channelCount, '$from');
    }
    return l.personVirtualChannelSubtitle(
        p.episodeCount, p.channelCount, '$from', '$to');
  }

  @override
  State<PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<PersonCard> {
  bool _hovering = false;

  /// Javna poveznica na profil — `/p/<slug>`, slug DOSLOVNO (bez `-`↔`_`
  /// pretvorbe koju rade kanali).
  String get _shareUrl => 'https://domovina.ai/p/${widget.person.slug}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Semantics(
      identifier: 'person-card-${widget.person.slug}',
      container: true,
      child: MouseRegion(
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
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PersonMonogram(
                          name: widget.person.name,
                          avatarUrl: widget.person.avatarUrl,
                          size: 132,
                          radius: 12,
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: _info(theme, l)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _info(ThemeData theme, AppLocalizations l) {
    final p = widget.person;
    final subtitle = PersonCard.subtitleOf(l, p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.personCardMeta(p.episodeCount, p.durationDisplay).toUpperCase(),
          style: AppTypography.eyebrowStyle(theme.colorScheme),
        ),
        const SizedBox(height: 6),
        Text(
          p.name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontFamily: 'Playfair Display',
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (p.avgMagisteriumScore != null) ...[
          const SizedBox(height: 10),
          _magisteriumPill(theme, l, p.avgMagisteriumScore!),
        ],
      ],
    );
  }

  /// Isti oblik kao pilula na kartici kanala — prazan score se graciozno ne
  /// crta (osobe iz starog agregata nemaju prosjek).
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
