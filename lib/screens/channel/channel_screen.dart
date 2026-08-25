import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';
import '../../models/channel_detail.dart';
import '../../pinka_sdk/pinka_sdk.dart';
import '../../services/channel_cache.dart';
import '../../services/follow_service.dart';
import '../../services/page_meta.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/magisterium_section.dart';
import '../../widgets/share_context_menu.dart';
import '../../widgets/cached_thumbnail.dart';

/// Channel detail screen — prikazuje listu video zapisa za određeni kanal.
///
/// Ruta: `/c/:slug` (slug = channel ID s `-` umjesto `_`).
///
/// Razdvojeno iz `lib/screens/home_screen.dart` u Korak 2 redizajna kao
/// move-only refactor. Funkcionalno identično `_VideoGridView` widgetu koji
/// je prije bio dio HomeScreen-a.
class ChannelScreen extends StatefulWidget {
  final String channelId;

  const ChannelScreen({super.key, required this.channelId});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  late final Future<ChannelDetail> _detailFuture;
  String? _resolvedName;
  // Kanonski UC… ID kanala (kad ga channel.json nosi) → otključava "Preuzmi
  // vlasništvo" akciju. Null dok pipeline ne upiše youtube_channel_id.
  String? _resolvedUcId;

  @override
  void initState() {
    super.initState();
    _detailFuture = channelCache.loadChannel(widget.channelId);
    // Runtime <title>/og meta — isti format kao worker edge-inject za /c/.
    _detailFuture.then((d) {
      if (!mounted) return;
      setPageMeta(
        title: '${d.name} — AI obrada podcasta – DOMOVINA.ai',
        description: d.description,
      );
    }).catchError((_) {});
  }

  void _back() {
    context.go('/');
  }

  void _openVideo(String videoId) {
    context.go('/v/$videoId');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: l.commonBack,
                    onPressed: _back,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _resolvedName ?? widget.channelId.replaceAll('_', ' '),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // „Prati" — lokalni popis praćenja (isti namespace kao osobe).
                  // Sam se sakrije dok je PersonChannelFlag ugašen.
                  FollowButton(
                    followKey: channelFollowKey(widget.channelId),
                    followLabel: l.channelFollow,
                    followingLabel: l.channelFollowing,
                  ),
                  // "Preuzmi vlasništvo" — vidljivo samo kad kanal ima kanonski
                  // UC… ID (Faza 0). Vodi na claim flow (/c/<slug>/claim).
                  if (_resolvedUcId != null)
                    IconButton(
                      icon: const Icon(Icons.verified_user_outlined),
                      tooltip: l.channelClaimOwnership,
                      onPressed: () => context.push(
                        '/c/${widget.channelId.replaceAll('_', '-')}/claim',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<ChannelDetail>(
                future: _detailFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        l.commonErrorWithDetails('${snap.error}'),
                      ),
                    );
                  }
                  final detail = snap.data!;
                  if (detail.name != _resolvedName ||
                      detail.youtubeChannelId != _resolvedUcId) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _resolvedName = detail.name;
                          _resolvedUcId = detail.youtubeChannelId;
                        });
                      }
                    });
                  }
                  final slug = widget.channelId.replaceAll('_', '-');
                  return Column(
                    children: [
                      // "Zid podrške" — sama se sakrije ako kanal nema aktivnu
                      // pinka kampanju (vidi lib/pinka_sdk/). Match po internom
                      // channel id-u ILI kanonskom UC… id-u.
                      PinkaSupportCard.channel(
                        channelId: widget.channelId,
                        youtubeChannelId: detail.youtubeChannelId,
                        onOpen: (_) => context.push(
                          Uri(
                            path: '/c/$slug/support',
                            queryParameters: {
                              if (detail.youtubeChannelId != null)
                                'uc': detail.youtubeChannelId!,
                              'name': detail.name,
                            },
                          ).toString(),
                        ),
                      ),
                      Expanded(
                        child: _ResponsiveVideoList(
                          videos: detail.videos,
                          onVideoTap: _openVideo,
                          isAudioSource: detail.isAudioSource,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponsiveVideoList extends StatelessWidget {
  final List<ChannelVideo> videos;
  final void Function(String videoId) onVideoTap;

  /// Kanal je audio-only izvor → kartice bez thumbnaila pokazuju "Audio Only".
  final bool isAudioSource;

  const _ResponsiveVideoList({
    required this.videos,
    required this.onVideoTap,
    required this.isAudioSource,
  });

  static const double _maxCardWidth = 300;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 600) {
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            itemCount: videos.length,
            itemBuilder: (context, i) => _VideoCard(
              video: videos[i],
              onTap: () => onVideoTap(videos[i].id),
              isAudioSource: isAudioSource,
            ),
          );
        }
        final availableWidth = width - 32;
        final columns = (availableWidth / _maxCardWidth).floor().clamp(2, 99);
        final cardWidth = (availableWidth - (columns - 1) * 12) / columns;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: videos
                .map(
                  (v) => SizedBox(
                    width: cardWidth,
                    child: _VideoGridCard(
                      video: v,
                      onTap: () => onVideoTap(v.id),
                      isAudioSource: isAudioSource,
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class _VideoCard extends StatelessWidget {
  final ChannelVideo video;
  final VoidCallback onTap;
  final bool isAudioSource;

  const _VideoCard({
    required this.video,
    required this.onTap,
    this.isAudioSource = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final hasArticle = video.pipeline?.hasArticle ?? false;
    // Audio-only kanali: nedostatak thumbnaila = audio epizoda → "Audio Only".
    Widget placeholder() => isAudioSource
        ? audioPlaceholder(theme, l, 120, 68)
        : videoPlaceholder(theme, 120, 68);

    return ShareContextMenu(
      url: 'https://domovina.ai/v/${video.id}',
      child: Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: video.thumbnail != null
                    ? CachedThumbnail(
                        url: video.thumbnail!,
                        width: 120,
                        height: 68,
                        fit: BoxFit.cover,
                        errorFallbackBuilder: (_) => placeholder(),
                      )
                    : placeholder(),
              ),
              const SizedBox(width: 12),
              Expanded(child: videoMeta(theme, l, video, hasArticle)),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _VideoGridCard extends StatelessWidget {
  final ChannelVideo video;
  final VoidCallback onTap;
  final bool isAudioSource;

  const _VideoGridCard({
    required this.video,
    required this.onTap,
    this.isAudioSource = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final hasArticle = video.pipeline?.hasArticle ?? false;
    // Audio-only kanali: nedostatak thumbnaila = audio epizoda → "Audio Only".
    Widget placeholder() =>
        isAudioSource ? audioPlaceholder(theme, l) : videoPlaceholder(theme);

    return ShareContextMenu(
      url: 'https://domovina.ai/v/${video.id}',
      child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: video.thumbnail != null
                  ? CachedThumbnail(
                      url: video.thumbnail!,
                      fit: BoxFit.cover,
                      errorFallbackBuilder: (_) => placeholder(),
                    )
                  : placeholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: videoMeta(theme, l, video, hasArticle),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared video card helpers — koriste se i u channel screenu i u home search
// rezultatima. Public da `lib/screens/home/*` može isto reusati.
// ---------------------------------------------------------------------------

Widget videoPlaceholder(ThemeData theme, [double? w, double? h]) => Container(
  width: w,
  height: h,
  color: theme.colorScheme.surfaceContainerHighest,
  child: Center(
    child: Icon(
      Icons.ondemand_video,
      color: theme.colorScheme.onSurfaceVariant,
    ),
  ),
);

/// "Audio Only" placeholder za epizode bez thumbnaila na audio-only kanalima
/// (vidi [ChannelDetail.isAudioSource]). Mali list-card ([h] ~68) prikazuje
/// samo ikonu; veći (grid 16:9) i tekst.
Widget audioPlaceholder(ThemeData theme, AppLocalizations l,
    [double? w, double? h]) {
  final compact = h != null && h < 90;
  return Container(
    width: w,
    height: h,
    color: theme.colorScheme.surfaceContainerHighest,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.podcasts, color: theme.colorScheme.onSurfaceVariant),
          if (!compact) ...[
            const SizedBox(height: 6),
            Text(
              l.channelAudioOnly,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget videoMeta(
  ThemeData theme,
  AppLocalizations l,
  ChannelVideo video,
  bool hasArticle,
) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      video.displayTitle,
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    const SizedBox(height: 4),
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (video.date != null)
          videoMetaChip(theme, Icons.calendar_today, video.date!),
        if (video.durationDisplay != null)
          videoMetaChip(theme, Icons.schedule, video.durationDisplay!),
      ],
    ),
    const SizedBox(height: 4),
    if (video.speakers.isNotEmpty)
      Text(
        video.speakers.join(', '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    const SizedBox(height: 6),
    Row(
      children: [
        if (video.magisteriumScore != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: MagisteriumSection.scoreColor(
                video.magisteriumScore,
              ).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: MagisteriumSection.scoreColor(
                  video.magisteriumScore,
                ).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.church,
                  size: 11,
                  color: MagisteriumSection.scoreColor(video.magisteriumScore),
                ),
                const SizedBox(width: 3),
                Text(
                  '${video.magisteriumScore}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: MagisteriumSection.scoreColor(
                      video.magisteriumScore,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (!hasArticle)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l.channelInProcessing,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ),
  ],
);

Widget videoMetaChip(ThemeData theme, IconData icon, String text) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
    const SizedBox(width: 3),
    Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  ],
);
