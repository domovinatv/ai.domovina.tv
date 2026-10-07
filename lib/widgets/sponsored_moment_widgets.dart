import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/sponsored_moment.dart';
import '../services/open_url.dart';
import '../services/sponsored_moments_controller.dart';
import '../theme/app_theme.dart';
import 'sponsors_in_video_section.dart' show formatSponsorClock;

/// Widgeti PLAĆENOG sponzorskog trenutka ([SponsoredMoment]).
///
/// Obrazac je preslikan iz `sponsors_in_video_section.dart` (traka u playeru,
/// oznaka u sekciji članka po vremenu), ali model, izvor i ton su odvojeni:
/// ovdje uvijek piše „Sponzorirano · {brand}" — ime onoga tko je platio
/// (DSA čl. 26) — a ne „Uz podršku". Boja je [AppTheme.sponsoredAccent], ne
/// `tertiary` autorovih sponzora.
///
/// Sva tri mjesta u playeru (oznaka preko videa, [VideoPanel], `_PlayerTab`)
/// slušaju ISTI [SponsoredMomentsController.active], pa nijedno ne računa
/// samo je li trenutak u tijeku.

/// Tap na poveznicu branda: mjerenje + otvaranje s `rel="sponsored"`.
void openSponsoredMoment(
  SponsoredMoment m,
  SponsoredMomentsController? controller,
) {
  final url = m.linkUrl;
  if (url == null) return;
  controller?.recordClick(m);
  openSponsoredUrl(url);
}

/// Oznaka preko slike dok trenutak svira. Renderira se kroz `controls:`
/// builder `EpisodeVideo`, pa postoji i u fullscreen ruti.
class SponsoredMomentVideoBadge extends StatelessWidget {
  final SponsoredMomentsController controller;

  const SponsoredMomentVideoBadge({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SponsoredMoment?>(
      valueListenable: controller.active,
      builder: (context, m, _) {
        if (m == null) return const SizedBox.shrink();
        final l = AppLocalizations.of(context);
        final label = Text(
          l.sponsoredBy(m.brand),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        );
        return Material(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: m.linkUrl == null
                ? null
                : () => openSponsoredMoment(m, controller),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: label),
                  if (m.linkUrl != null) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.open_in_new,
                      size: 12,
                      color: Colors.white70,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Traka u panelu playera ([VideoPanel]) i u jednostavnom prikazu
/// (`_PlayerTab`). Jedan trenutak = jedan redak: „Sponzorirano · Brand",
/// rečenica, pa gumbi („Poslušaj · 0:44", poveznica). Trenutak koji upravo
/// svira je istaknut.
///
/// Druga i treća pozivna točka nisu kozmetika: na **audio-only** epizodi
/// slike nema, pa oznake preko videa ni ne postoji — ova traka je jedino
/// mjesto gdje slušatelj vidi tko je platio.
class SponsoredMomentsPlayerStrip extends StatelessWidget {
  final SponsoredMomentsController? controller;

  /// Skok na početak trenutka; null dok player nije spreman.
  final void Function(SponsoredMoment moment)? onListen;

  const SponsoredMomentsPlayerStrip({
    super.key,
    required this.controller,
    this.onListen,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null || c.moments.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder<SponsoredMoment?>(
      valueListenable: c.active,
      builder: (context, active, _) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in c.moments.moments)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SponsoredMomentCard(
                  moment: m,
                  active: identical(m, active),
                  controller: c,
                  onListen: onListen,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Jedan plaćeni trenutak u traci playera. Javan jer ga checkout koristi kao
/// pregled („ovako će oglas izgledati") — isti widget, ne kopija.
class SponsoredMomentCard extends StatelessWidget {
  final SponsoredMoment moment;
  final bool active;

  /// Null u pregledu: tap na poveznicu se tada ne mjeri.
  final SponsoredMomentsController? controller;
  final void Function(SponsoredMoment moment)? onListen;

  const SponsoredMomentCard({
    super.key,
    required this.moment,
    required this.active,
    this.controller,
    this.onListen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final accent = AppTheme.sponsoredAccent(theme.brightness);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: accent, width: active ? 4 : 2),
        ),
        color: active
            ? accent.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (moment.logoUrl != null) ...[
                _Logo(url: moment.logoUrl!, size: 20),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: l.sponsoredLabel,
                        style: TextStyle(color: muted),
                      ),
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text: moment.brand,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 6),
                Text(
                  l.sponsoredNow,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          if (moment.tagline != null) ...[
            const SizedBox(height: 2),
            Text(
              moment.tagline!,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(
                  '${l.sponsoredListen} · ${formatSponsorClock(moment.start)}',
                ),
                onPressed: onListen == null ? null : () => onListen!(moment),
              ),
              if (moment.linkUrl != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(
                    moment.linkHost ?? l.sponsoredWebsite,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => openSponsoredMoment(moment, controller),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Oznaka u sekciji članka u koju PADA POČETAK trenutka (sidro je vrijeme,
/// vidi [SponsoredMoments.marksBySection]). Prigušena kao oznaka autorovih
/// sponzora, ali sa zlatnim rubom i riječju „Sponzorirano".
class SponsoredMomentSectionMark extends StatelessWidget {
  final List<SponsoredMoment> moments;
  final SponsoredMomentsController? controller;
  final void Function(SponsoredMoment moment)? onListen;

  const SponsoredMomentSectionMark({
    super.key,
    required this.moments,
    this.controller,
    this.onListen,
  });

  @override
  Widget build(BuildContext context) {
    if (moments.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final accent = AppTheme.sponsoredAccent(theme.brightness);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in moments) ...[
              Text(
                l.sponsoredAt(formatSponsorClock(m.start)),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: muted,
                ),
              ),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: l.sponsoredPaidBy(m.brand)),
                    if (m.tagline != null)
                      TextSpan(
                        text: ' — ${m.tagline}',
                        style: TextStyle(color: muted),
                      ),
                  ],
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text(l.sponsoredListen),
                    onPressed: onListen == null ? null : () => onListen!(m),
                  ),
                  if (m.linkUrl != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(m.linkHost ?? l.sponsoredWebsite),
                      onPressed: () => openSponsoredMoment(m, controller),
                    ),
                ],
              ),
              if (m != moments.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Logo branda s našeg Storagea. `Image.network` (ne `CachedThumbnail`):
/// host je `api.domovina.ai`, a `CachedThumbnail` je samo za CDN slike epizoda.
class _Logo extends StatelessWidget {
  final String url;
  final double size;

  const _Logo({required this.url, required this.size});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
    ),
  );
}
