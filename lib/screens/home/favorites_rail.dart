import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/cdn_config.dart';
import '../../services/channel_cache.dart';
import '../../services/favorites_service.dart';
import '../favorites/favorites_resolver.dart';
import 'episode_rail_card.dart';
import 'episodes_rail.dart';
import '../../router/nav.dart';

/// Home rail „Tvoje spremljeno" — epizode koje je korisnik lajkao (srce),
/// **najnovija prvo**. Isječak; puni popis je na `/favorites`.
///
/// Widget je samodostatan (isti obrazac kao `FollowedRail`): sam učita favorite
/// i sluša katalog, i sam se sakrije kad nema nijednog spremljenog. Home time
/// dobiva jednu liniju.
///
/// Radi i za anonimne korisnike — favoriti su offline-first (localStorage);
/// prijava ih samo sinkronizira preko uređaja (vidi [FavoritesService]).
class FavoritesRail extends StatefulWidget {
  final bool isMobile;

  /// Otvaranje epizode ide kroz home (poštuje „Jednostavno" mod → `/m/:id`).
  final void Function(String videoId) onVideoTap;

  /// Koliko kartica stane u rail prije nego se ide na puni popis.
  final int limit;

  const FavoritesRail({
    super.key,
    required this.isMobile,
    required this.onVideoTap,
    this.limit = 12,
  });

  @override
  State<FavoritesRail> createState() => _FavoritesRailState();
}

class _FavoritesRailState extends State<FavoritesRail> {
  List<FavoriteEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    FavoritesService.instance.addListener(_reload);
    // Katalog puni naslove/datume kartica — bez ovoga bi rail nakon prvog
    // frame-a ostao na denorm fallbacku.
    channelCache.addListener(_onCatalogChanged);
    _reload();
  }

  @override
  void dispose() {
    FavoritesService.instance.removeListener(_reload);
    channelCache.removeListener(_onCatalogChanged);
    super.dispose();
  }

  void _onCatalogChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final list = await FavoritesService.instance.entries();
    if (mounted) setState(() => _entries = list);
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final items = resolveFavorites(
      _entries.take(widget.limit).toList(),
    );

    return Semantics(
      identifier: 'home-favorites-rail',
      container: true,
      child: EpisodesRail(
        eyebrow: l.homeRailFavorites,
        isMobile: widget.isMobile,
        // Uvijek vidljivo, i kad rail ne reže popis — to je jedini ulaz u
        // policu s naslovnice (drugi je stavka na `/account`).
        onSeeAll: () => drillDown(context, '/favorites'),
        seeAllLabel: l.commonSeeAll,
        cards: [
          for (final item in items)
            EpisodeRailCard(
              title: item.title,
              subtitle: item.channelName,
              // Thumbnail uvijek s našeg CDN-a (ytimg URL-ovi ruše CORS na webu).
              thumbnailUrl: CdnConfig.thumbnailUrl(item.episodeId),
              dateLabel: item.date,
              magisteriumScore: item.magisteriumScore,
              width: widget.isMobile ? 180 : 220,
              shareUrl: 'https://domovina.ai/v/${item.episodeId}',
              onTap: () => widget.onVideoTap(item.episodeId),
            ),
        ],
      ),
    );
  }
}
