import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/channel_index.dart';
import '../../services/cdn_config.dart';
import '../../services/channel_cache.dart';
import '../../services/follow_service.dart';
import '../../services/person_channel_flag.dart';
import '../../services/person_index_cache.dart';
import 'episode_rail_card.dart';
import 'episodes_rail.dart';

/// Home rail „Novo od praćenih" — po jedna najnovija epizoda za svaki praćeni
/// kanal i osobu, ali **samo ako je korisnik nije već vidio**.
///
/// Push notifikacija u prvom krugu nema (odluka O10 u
/// `docs/plans/virtualni-kanali.md`): diff je čisto klijentski — `latest_video`
/// iz `ChannelIndex` odnosno `latest_episode` iz person indeksa naspram zadnje
/// viđenog datuma u [FollowService]. Tap otvara epizodu i **označava je
/// viđenom**, pa stavka nestane iz raila.
///
/// Widget je samodostatan (isti obrazac kao `PersonsRail`): sam učita popis
/// praćenja i indekse, i sam se sakrije kad je feature flag ugašen, kad nema
/// praćenja ili kad nema ničeg novog. Home time dobiva jednu liniju.
class FollowedRail extends StatefulWidget {
  final bool isMobile;

  /// Otvaranje epizode ide kroz home (poštuje „Jednostavno" mod → `/m/:id`).
  final void Function(String videoId) onVideoTap;

  const FollowedRail({
    super.key,
    required this.isMobile,
    required this.onVideoTap,
  });

  @override
  State<FollowedRail> createState() => _FollowedRailState();
}

class _FollowedRailState extends State<FollowedRail> {
  /// Na PONOVNOM montiranju (povratak na naslovnicu) je flag već učitan, pa
  /// krećemo od stvarne vrijednosti umjesto od `false` — inače rail jedan frame
  /// stoji prazan i visina naslovnice poskoči.
  bool _flagOn = PersonChannelFlag.instance.isOnIfLoaded ?? false;

  @override
  void initState() {
    super.initState();
    // Flag/popis se čitaju izvan build faze — `PersonChannelFlag.isOn` pri
    // prvom čitanju može sinkrono pozvati notifyListeners().
    PersonChannelFlag.instance.addListener(_onFlagChanged);
    FollowService.instance.addListener(_onDataChanged);
    channelCache.addListener(_onDataChanged);
    personIndexCache.addListener(_onDataChanged);
    unawaited(Future.microtask(_bootstrap));
  }

  Future<void> _bootstrap() async {
    unawaited(personIndexCache.loadIndex());
    await FollowService.instance.ensureLoaded();
    await PersonChannelFlag.instance.init();
    _onDataChanged();
    _onFlagChanged();
  }

  void _onFlagChanged() {
    final on = PersonChannelFlag.instance.isOn;
    if (!mounted || on == _flagOn) return;
    setState(() => _flagOn = on);
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PersonChannelFlag.instance.removeListener(_onFlagChanged);
    FollowService.instance.removeListener(_onDataChanged);
    channelCache.removeListener(_onDataChanged);
    personIndexCache.removeListener(_onDataChanged);
    super.dispose();
  }

  ChannelSummary? _channelById(String id) {
    for (final c in channelCache.index?.channels ?? const <ChannelSummary>[]) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Praćeni entiteti koji imaju epizodu noviju od zadnje viđene, najnoviji prvi.
  List<_FollowedItem> _items() {
    final follows = FollowService.instance;
    final items = <_FollowedItem>[];

    for (final key in follows.all) {
      final channelId = channelIdFromFollowKey(key);
      if (channelId != null) {
        final channel = _channelById(channelId);
        final latest = channel?.latestVideo;
        if (channel == null || latest == null) continue;
        if (!follows.hasUnseen(key, latest.date)) continue;
        items.add(_FollowedItem(
          followKey: key,
          videoId: latest.id,
          title: latest.title,
          source: channel.name,
          date: latest.date,
        ));
        continue;
      }

      final slug = personSlugFromFollowKey(key);
      if (slug == null) continue;
      final person = personIndexCache.bySlug(slug);
      final latest = person?.latestEpisode;
      if (person == null || latest == null) continue;
      if (!follows.hasUnseen(key, latest.date)) continue;
      items.add(_FollowedItem(
        followKey: key,
        videoId: latest.youtubeId,
        title: latest.title,
        source: person.name,
        date: latest.date,
      ));
    }

    // ISO datumi → leksikografski sort je i kronološki, bez ovisnosti o danas.
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  Future<void> _open(_FollowedItem item) async {
    // Označi viđenim PRIJE navigacije — povratak na home tada više ne pokazuje
    // istu epizodu kao „novo".
    await FollowService.instance.markSeen(item.followKey, item.date);
    if (!mounted) return;
    widget.onVideoTap(item.videoId);
  }

  @override
  Widget build(BuildContext context) {
    if (!_flagOn) return const SizedBox.shrink();
    final items = _items();
    if (items.isEmpty) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);

    return Semantics(
      identifier: 'home-followed-rail',
      container: true,
      child: EpisodesRail(
        eyebrow: l.homeFollowedRailTitle,
        isMobile: widget.isMobile,
        cards: [
          for (final item in items)
            EpisodeRailCard(
              title: item.title.isEmpty ? item.videoId : item.title,
              subtitle: item.source,
              // Thumbnail uvijek s našeg CDN-a (ytimg URL-ovi ruše CORS na webu).
              thumbnailUrl: CdnConfig.thumbnailUrl(item.videoId),
              dateLabel: item.date,
              width: widget.isMobile ? 180 : 220,
              shareUrl: 'https://domovina.ai/v/${item.videoId}',
              onTap: () => unawaited(_open(item)),
            ),
        ],
      ),
    );
  }
}

/// Jedna stavka raila — ravan zapis neovisan o tome je li izvor kanal ili osoba.
class _FollowedItem {
  final String followKey;
  final String videoId;
  final String title;

  /// Ime kanala ili osobe — podnaslov kartice.
  final String source;
  final String date;

  const _FollowedItem({
    required this.followKey,
    required this.videoId,
    required this.title,
    required this.source,
    required this.date,
  });
}
