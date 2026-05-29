import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/channel_index.dart';
import '../../models/channel_detail.dart';
import '../../services/cdn_config.dart';
import '../../services/channel_cache.dart';
import '../../services/search_service.dart';
import '../../utils/text_search.dart';

import '../../theme/typography.dart';

/// Otvori search overlay (modal) povrh home screen-a.
///
/// Dva sloja pretrage:
/// - Tier 0 (instant, offline): dijakritik-neosjetljiv lokalni match nad
///   učitanim kanalima/epizodama (naslov, govornici, teme, sažetak).
/// - Tier 1 (semantic, online): deterministički RAG `/api/search` — pronalazi
///   GDJE se o nečemu priča, s deep linkom na točan timestamp.
Future<void> showSearchOverlay(
  BuildContext context, {
  required List<ChannelSummary> channels,
  required void Function(ChannelSummary) onSelectChannel,
  required void Function(String videoId) onSelectVideo,
  required void Function(String videoId, int seconds) onSelectVideoAt,
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
      onSelectVideoAt: onSelectVideoAt,
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
  final void Function(String videoId, int seconds) onSelectVideoAt;

  const _SearchOverlay({
    required this.channels,
    required this.onSelectChannel,
    required this.onSelectVideo,
    required this.onSelectVideoAt,
  });

  @override
  State<_SearchOverlay> createState() => _SearchOverlayState();
}

// Lokalni rezultat epizode s izračunatim scoreom.
typedef _VideoHit = ({String channelId, String channelName, ChannelVideo video});

class _SearchOverlayState extends State<_SearchOverlay> {
  final _searchController = TextEditingController();
  final _idController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  Timer? _semanticDebounce;
  String _query = '';
  bool _showIdInput = false;

  // Tier 1 semantic state.
  List<SemanticResult> _semanticResults = [];
  bool _semanticLoading = false;

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
    _semanticDebounce?.cancel();
    _searchController.dispose();
    _idController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Tier 0 — instant lokalni rezultati (kratki debounce za smoothness).
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = value);
    });

    // Tier 1 — semantic, duži debounce + min duljina (štedi mrežu/embeddinge).
    _semanticDebounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      if (_semanticResults.isNotEmpty || _semanticLoading) {
        setState(() {
          _semanticResults = [];
          _semanticLoading = false;
        });
      }
      return;
    }
    _semanticDebounce = Timer(const Duration(milliseconds: 420), () {
      _runSemantic(q);
    });
  }

  Future<void> _runSemantic(String q) async {
    setState(() => _semanticLoading = true);
    final results = await SearchService.search(q, limit: 12);
    if (!mounted) return;
    // Odbaci stale odgovor (upit se promijenio u međuvremenu).
    if (_searchController.text.trim() != q) return;
    setState(() {
      _semanticResults = results;
      _semanticLoading = false;
    });
  }

  void _openVideoId() {
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    Navigator.of(context).pop();
    widget.onSelectVideo(id);
  }

  // ── Tier 0 scoring ────────────────────────────────────────────
  List<ChannelSummary> _localChannels(String q) {
    final scored = <(double, ChannelSummary)>[];
    for (final ch in widget.channels) {
      final s = localMatchScore(q, ch.name);
      if (s > 0) scored.add((s, ch));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.take(6).map((e) => e.$2).toList();
  }

  List<_VideoHit> _localVideos(String q) {
    final scored = <(double, _VideoHit)>[];
    for (final hit in channelCache.allVideos) {
      final v = hit.video;
      // Kombinirani haystack → multi-token upit radi i preko više polja
      // (npr. "šterc demografija": ime u speakers, tema u topics).
      final combined = [
        v.displayTitle,
        v.title,
        v.speakers.join(' '),
        v.topics.join(' '),
        v.abstract_ ?? '',
        hit.channelName,
      ].join('  ');
      final base = localMatchScore(q, combined);
      if (base <= 0) continue;
      final titleBoost = localMatchScore(q, v.displayTitle) > 0 ? 3.0 : 0.0;
      scored.add((base + titleBoost, hit));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.take(12).map((e) => e.$2).toList();
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
                hintText: 'Pretraži kanale, epizode i sadržaj…',
                hintStyle: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5),
                  fontWeight: FontWeight.w400,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_semanticLoading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
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

    final channelResults = _localChannels(_query);
    final videoResults =
        channelCache.allVideos.isNotEmpty ? _localVideos(_query) : <_VideoHit>[];

    final hasLocal = channelResults.isNotEmpty || videoResults.isNotEmpty;
    final hasSemantic = _semanticResults.isNotEmpty;

    if (!hasLocal && !hasSemantic && !_semanticLoading) {
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
          for (final ch in channelResults) _channelRow(theme, ch),
        ],
        if (videoResults.isNotEmpty) ...[
          _sectionLabel(theme, 'EPIZODE'),
          for (final vr in videoResults) _videoRow(theme, vr),
        ],
        // Tier 1 — semantička pretraga sadržaja.
        if (hasSemantic || _semanticLoading) ...[
          _semanticSectionLabel(theme),
          if (hasSemantic)
            for (final r in _semanticResults) _semanticRow(theme, r)
          else
            _semanticLoadingRow(theme),
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
              'Počni tipkati za pretragu',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pretražuje kanale, epizode i sam sadržaj razgovora',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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

  Widget _semanticSectionLabel(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
      child: Row(
        children: [
          Icon(Icons.auto_awesome,
              size: 13, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            'U SADRŽAJU',
            style: AppTypography.eyebrowStyle(theme.colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _semanticLoadingRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Pretražujem sadržaj razgovora…',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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

  Widget _videoRow(ThemeData theme, _VideoHit vr) {
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
                errorBuilder: (c, e, s) => _thumbPlaceholder(theme, 72, 40),
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

  Widget _semanticRow(ThemeData theme, SemanticResult r) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        if (r.isSummary) {
          widget.onSelectVideo(r.youtubeId);
        } else {
          widget.onSelectVideoAt(r.youtubeId, r.startSeconds);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                CdnConfig.thumbnailUrl(r.youtubeId),
                width: 72,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => _thumbPlaceholder(theme, 72, 40),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.episodeTitle != null)
                    Text(
                      r.episodeTitle!,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    r.snippet,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (!r.isSummary) ...[
                        Icon(Icons.play_circle_outline,
                            size: 12, color: theme.colorScheme.primary),
                        const SizedBox(width: 3),
                        Text(
                          _fmtTs(r.startSeconds),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          r.speakers.isNotEmpty
                              ? r.speakers.join(', ')
                              : r.channel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
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
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
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

  String _fmtTs(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final ss = sec.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }
}
