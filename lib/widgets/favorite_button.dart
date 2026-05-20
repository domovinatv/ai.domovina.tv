/// Heart toggle za favorite. Prvi put kad anonimni user doda favorit, okida
/// M3 inline prompt za sinkronizaciju.
library;

import 'package:flutter/material.dart';
import '../onboarding/moments/m3_favorite_sync_inline.dart';
import '../services/favorites_service.dart';

class FavoriteButton extends StatefulWidget {
  final String episodeId;
  final double iconSize;
  final Color? activeColor;

  const FavoriteButton({
    super.key,
    required this.episodeId,
    this.iconSize = 24,
    this.activeColor,
  });

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  bool? _isFav;

  @override
  void initState() {
    super.initState();
    _load();
    FavoritesService.instance.addListener(_load);
  }

  @override
  void didUpdateWidget(covariant FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodeId != widget.episodeId) {
      _load();
    }
  }

  @override
  void dispose() {
    FavoritesService.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final v = await FavoritesService.instance.isFavorite(widget.episodeId);
    if (mounted) setState(() => _isFav = v);
  }

  Future<void> _toggle() async {
    final wasAdded =
        await FavoritesService.instance.toggle(widget.episodeId);
    if (!mounted) return;
    if (wasAdded) {
      await maybeShowM3OnFavorite(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFav = _isFav ?? false;
    final color = widget.activeColor ?? const Color(0xFFFF0000);

    return IconButton(
      tooltip: isFav ? 'Ukloni iz favorita' : 'Dodaj u favorite',
      onPressed: _toggle,
      icon: Icon(
        isFav ? Icons.favorite : Icons.favorite_border,
        size: widget.iconSize,
        color: isFav ? color : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
