import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fuzzy/fuzzy.dart';
import '../../models/channel_index.dart';
import '../../models/channel_detail.dart';
import '../../services/cdn_config.dart';
import '../../services/channel_cache.dart';
import '../../theme/app_theme.dart';
import '../../theme/typography.dart';

/// Otvori search overlay (modal) povrh home screen-a.
///
/// Sadrži:
/// - Glavni search field s autofocus
/// - Live rezultati: kanali (do 8) + epizode (do 15)
/// - Expandable sekcija "Otvori po YouTube ID-u" na dnu
Future<void> showSearchOverlay(
  BuildContext context, {
  required List<ChannelSummary> channels,
  required void Function(ChannelSummary) onSelectChannel,
  required void Function(String videoId) onSelectVideo,
}) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Zatvori pretragu',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => _SearchOverlay(
      channels: channels,
      onSelectChannel: onSelectChannel,
      onSelectVideo: onSelectVideo,
    ),
    transitionBuilder: (context, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class _SearchOverlay extends StatefulWidget {
  final List<ChannelSummary> channels;
  final void Function(ChannelSummary) onSelectChannel;
  final void Function(String videoId) onSelectVideo;

  const _SearchOverlay({
    required this.channels,
    required this.onSelectChannel,
    required this.onSelectVideo,
  });

  @override
  State<_SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<_SearchOverlay> {
  final _searchController = TextEditingController();
  final _idController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _showIdInput = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _idController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _openVideoId() {
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    Navigator.of(context).pop();
    widget.onSelectVideo(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final maxWidth = size.width < 700 ? size.width - 24 : 640.0;
    final maxHeight = size.height * 0.8;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _searchHeader(theme),
                const Divider(height: 1),
                Flexible(child: _resultsList(theme)),
                const Divider(height: 1),
                _idInputSection(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          Icon(Icons.search,
              size: 22, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              style: theme.textTheme.titleMedium,
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: 'Pretrazi kanale i epizode...',
                hintStyle: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5),
                  fontWeight: FontWeight.w400,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Zatvori',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _resultsList(ThemeData theme) {
    if (_query.isEmpty) {
      return _emptyState(theme);
    }

    // Fuzzy search po kanalima.
    final channelFuse = Fuzzy<ChannelSummary>(
      widget.channels,
      options: FuzzyOptions(
        keys: [WeightedKey(name: 'name', getter: (c) => c.name, weight: 1)],
        threshold: 0.4,
      ),
    );
    final channelResults =
        channelFuse.search(_query).take(8).map((r) => r.item).toList();

    // Fuzzy search po video zapisima (ako je cache spreman).
    final allVids = channelCache.allVideos;
    List<({String channelId, String channelName, ChannelVideo video})>
        videoResults = [];
    if (allVids.isNotEmpty) {
      final videoFuse = Fuzzy<
          ({String channelId, String channelName, ChannelVideo video})>(
        allVids,
        options: FuzzyOptions(
          keys: [
            WeightedKey(
              name: 'title',
              getter: (v) => v.video.displayTitle,
              weight: 1,
            ),
            WeightedKey(
              name: 'speakers',
              getter: (v) => v.video.speakers.join(' '),
              weight: 0.5,
            ),
          ],
          threshold: 0.4,
        ),
      );
      videoResults =
          videoFuse.search(_query).take(15).map((r) => r.item).toList();
    }

    if (channelResults.isEmpty && videoResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'Nema rezultata za "$_query"',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (channelResults.isNotEmpty) ...[
          _sectionLabel(theme, 'KANALI'),
          for (final ch in channelResults)
            _channelRow(theme, ch),
        ],
        if (videoResults.isNotEmpty) ...[
          _sectionLabel(theme, 'EPIZODE'),
          for (final vr in videoResults) _videoRow(theme, vr),
        ],
      ],
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(36),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_outlined,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Pocni tipkati da pretrazis',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
      child: Text(
        text,
        style: AppTypography.eyebrowStyle(theme.colorScheme),
      ),
    );
  }

  Widget _channelRow(ThemeData theme, ChannelSummary ch) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        widget.onSelectChannel(ch);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ch.avatarSquare != null
                  ? Image.network(
                      ch.avatarSquare!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => _placeholder(theme, 40),
                    )
                  : _placeholder(theme, 40),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ch.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${ch.videoCount} epizoda · ${ch.durationDisplay}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _videoRow(ThemeData theme,
      ({String channelId, String channelName, ChannelVideo video}) vr) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        widget.onSelectVideo(vr.video.id);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                CdnConfig.thumbnailUrl(vr.video.id),
                width: 72,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) =>
                    _thumbPlaceholder(theme, 72, 40),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vr.video.displayTitle,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    vr.channelName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (vr.video.durationDisplay != null)
              Text(
                vr.video.durationDisplay!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _idInputSection(ThemeData theme) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showIdInput = !_showIdInput),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _showIdInput
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Otvori po YouTube ID-u',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showIdInput)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _idController,
                      style: theme.textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        hintText: 'npr. H-p2Hl6x7I0',
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _openVideoId(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _openVideoId,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.croBlue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Icon(Icons.play_arrow, size: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(ThemeData theme, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.podcasts,
          size: size * 0.5,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
    );
  }

  Widget _thumbPlaceholder(ThemeData theme, double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.ondemand_video,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
    );
  }
}
