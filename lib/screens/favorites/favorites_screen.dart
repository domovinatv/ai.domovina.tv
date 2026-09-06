import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart' show log;
import '../../services/cdn_config.dart';
import '../../services/channel_cache.dart';
import '../../services/favorites_service.dart';
import '../../services/view_mode.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cached_thumbnail.dart';
import 'favorites_resolver.dart';
import '../../router/nav.dart';

/// Puni popis spremljenih (lajkanih) epizoda — najnovija prvo.
///
/// Pandan raila „Tvoje spremljeno" na naslovnici (`FavoritesRail`), samo bez
/// reza: ovdje stoji cijela povijest. Ulazi: rail („Prikaži sve"), stavka na
/// ekranu računa i direktni `/favorites` deep-link.
///
/// Self-contained: sam podigne katalog (`channelCache`) kad se otvori direktno,
/// jer bez njega imamo samo denorm naslov iz lokalnog zapisa.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<FavoriteEntry>? _entries;
  bool _simpleMode = false;

  @override
  void initState() {
    super.initState();
    FavoritesService.instance.addListener(_reload);
    channelCache.addListener(_onCatalogChanged);
    _reload();
    _loadSimpleMode();
    _ensureCatalog();
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

  Future<void> _loadSimpleMode() async {
    final saved = await loadSimpleModePref();
    if (mounted) setState(() => _simpleMode = saved ?? false);
  }

  /// Deep-link na `/favorites` ne prolazi kroz home, pa katalog možda nije
  /// dignut — bez njega su naslovi samo denorm fallback. `prefetchAll` ima
  /// vlastiti guard protiv dvostrukog pokretanja.
  Future<void> _ensureCatalog() async {
    try {
      final index = channelCache.index ?? await channelCache.loadIndex();
      await channelCache.prefetchAll(index.channels);
    } catch (e) {
      log('FavoritesScreen._ensureCatalog ERROR: $e');
    }
  }

  void _open(String videoId) {
    drillDown(context, _simpleMode ? '/m/$videoId' : '/v/$videoId');
  }

  Future<void> _remove(ResolvedFavorite item) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final entry = item.entry;
    await FavoritesService.instance.remove(entry.episodeId);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.favoritesRemoved),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: l.commonUndo,
          // Vrati s izvornim naslovom/kanalom; vrijeme spremanja se resetira na
          // sada (lokalni zapis nema mjesta za „bilo je ovdje") — stavka se
          // zato vrati na vrh liste.
          onPressed: () => FavoritesService.instance.toggle(
            entry.episodeId,
            title: item.title,
            channelName: item.channelName,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final entries = _entries;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(l.favoritesTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l.commonBack,
          onPressed: () => back(context),
        ),
      ),
      body: SafeArea(
        top: false,
        child: entries == null
            ? const Center(child: CircularProgressIndicator())
            : entries.isEmpty
                ? _empty(theme, l)
                : _list(theme, l, resolveFavorites(entries)),
      ),
    );
  }

  Widget _empty(ThemeData theme, AppLocalizations l) {
    final cs = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border, size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                l.favoritesEmptyTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                l.favoritesEmptyBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.explore_outlined),
                label: Text(l.favoritesBrowse),
                onPressed: () => context.go('/'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(
      ThemeData theme, AppLocalizations l, List<ResolvedFavorite> items) {
    // Rubni padding ide UNUTAR scrollabla (vidi CLAUDE.md — Scrollabilne liste).
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l.favoritesCount(items.length),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return _row(theme, l, items[i - 1]);
          },
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, AppLocalizations l, ResolvedFavorite item) {
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(item.episodeId),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 128,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedThumbnail(
                      url: CdnConfig.thumbnailUrl(item.episodeId),
                      width: 128,
                      fit: BoxFit.cover,
                      errorIcon: Icons.ondemand_video,
                      errorIconSize: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.channelName != null) ...[
                      Text(
                        item.channelName!.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      item.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.date != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.date!,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: l.mediaRemoveFavorite,
                icon: const Icon(Icons.favorite),
                color: AppTheme.croRed,
                onPressed: () => _remove(item),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
