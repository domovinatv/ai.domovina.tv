import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/person_hub.dart';
import '../../services/person_channel_flag.dart';
import '../../services/person_index_cache.dart';
import '../../widgets/person_monogram.dart';
import '../../widgets/share_context_menu.dart';
import 'episodes_rail.dart';
import '../../router/nav.dart';

/// Home rail „Osobe" — virtualni kanali (osobe) u istom editorial obliku kao
/// ostali railovi na naslovnici.
///
/// Zašto rail, a ne uklapanje u kanalski prikaz: home je namjerno olakšan
/// (puni popis kanala je premješten na `/channels` zbog scroll-perfa), pa osobe
/// ulaze kao dodatna lagana traka koja ne dira postojeći tok (odluka O9 u
/// `docs/plans/virtualni-kanali.md`).
///
/// Widget je **samodostatan**: sam učita indeks, sam se sakrije kad je feature
/// flag ugašen, kad indeks nije dostupan (stari backend bez `/api/persons`)
/// ili kad nema nijedne osobe iznad praga. Home time dobiva jednu liniju, bez
/// novog stanja u `home_screen.dart`.
class PersonsRail extends StatefulWidget {
  final bool isMobile;

  /// Koliko osoba stane u rail prije „Prikaži sve".
  ///
  /// `EpisodesRail` prima gotovu listu widgeta, pa bi bez kapice home gradio
  /// karticu za SVAKU osobu u indeksu (74 na dan 4.9.2026.) pri svakom
  /// buildu — na stranici koja je namjerno olakšana zbog scroll-perfa. Ista
  /// vrijednost kao `FavoritesRail.limit`.
  final int limit;

  const PersonsRail({
    super.key,
    required this.isMobile,
    this.limit = 12,
  });

  @override
  State<PersonsRail> createState() => _PersonsRailState();
}

class _PersonsRailState extends State<PersonsRail> {
  bool _flagOn = false;

  @override
  void initState() {
    super.initState();
    // Flag i indeks se čitaju IZVAN build faze i drže u lokalnom stanju.
    // `PersonChannelFlag.isOn` pri PRVOM čitanju pokreće `_load()`, koji u
    // `?vk=1` grani zove `notifyListeners()` SINKRONO — čitanje iz build()-a
    // (npr. pod `ListenableBuilder`-om) srušilo bi frame. Zato: init u
    // microtasku, pa setState kad vrijednost stigne.
    PersonChannelFlag.instance.addListener(_onFlagChanged);
    personIndexCache.addListener(_onIndexChanged);
    unawaited(Future.microtask(_bootstrap));
  }

  Future<void> _bootstrap() async {
    unawaited(personIndexCache.loadIndex());
    await PersonChannelFlag.instance.init();
    _onFlagChanged();
  }

  void _onFlagChanged() {
    final on = PersonChannelFlag.instance.isOn;
    if (!mounted || on == _flagOn) return;
    setState(() => _flagOn = on);
  }

  void _onIndexChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PersonChannelFlag.instance.removeListener(_onFlagChanged);
    personIndexCache.removeListener(_onIndexChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_flagOn) return const SizedBox.shrink();
    final persons = personIndexCache.virtualChannels;
    if (persons.isEmpty) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    final width = widget.isMobile ? 140.0 : 160.0;

    return Semantics(
      identifier: 'home-persons-rail',
      container: true,
      child: EpisodesRail(
        eyebrow: l.homePersonsRailTitle,
        isMobile: widget.isMobile,
        // Rail pokazuje samo vrh popisa; „Prikaži sve" vodi u isti katalog u
        // kojem žive i kanali, s već odabranim filtrom „Osobe".
        onSeeAll: () => drillDown(context, '/channels?prikaz=osobe'),
        seeAllLabel: l.commonSeeAll,
        cards: [
          for (final p in persons.take(widget.limit))
            _PersonRailTile(
              person: p,
              width: width,
              onTap: () => drillDown(context, p.routePath),
            ),
        ],
      ),
    );
  }
}

/// Uska kartica osobe za horizontalni rail — monogram, ime, broj epizoda.
///
/// Namjerno je uža i tiša od `PersonCard` u katalogu: rail je pregled, ne
/// katalog. Puni agregat (kanali, godine) čeka na `/p/:slug`.
class _PersonRailTile extends StatelessWidget {
  final PersonSummary person;
  final double width;
  final VoidCallback onTap;

  const _PersonRailTile({
    required this.person,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Semantics(
      identifier: 'person-card-${person.slug}',
      container: true,
      child: ShareContextMenu(
        url: 'https://domovina.ai/p/${person.slug}',
        child: SizedBox(
          width: width,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PersonMonogram(
                    name: person.name,
                    avatarUrl: person.avatarUrl,
                    size: width,
                    radius: 12,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    person.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.personEpisodesCount(person.episodeCount),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
