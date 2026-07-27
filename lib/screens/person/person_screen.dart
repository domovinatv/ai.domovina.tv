import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../models/person_hub.dart';
import '../../services/cdn_config.dart';
import '../../services/page_meta.dart';
import '../../services/person_service.dart';
import '../../theme/app_theme.dart';

/// Javni profil osobe ("person hub") — /p/:slug.
///
/// Dohvaća agregat SVIH epizoda u kojima se osoba pojavljuje (kroz sve kanale) s
/// domovina-rag `/api/person/{slug}` i prikazuje: ime + avatar, statistiku
/// (epizode / kanali / spomeni), raspodjelu po kanalima, mjesečni timeline te
/// dva popisa epizoda — „Epizode" (govori) i „Spominje se u". Prazno/404 stanje
/// tek ako slug nije ni govornik ni spomen.
///
/// Osoba koja se SAMO spominje (nikad gost — povijesna/pokojna figura) ima
/// valjan profil: govor-agregacije su prazne, pa se raspodjela po kanalima i
/// timeline crtaju iz spomena ([PersonHub.mentionChannels]/`mentionTimeline`).
///
/// Slug se prosljeđuje DOSLOVNO iz rute (bez `-`↔`_` transformacije koju rade
/// kanali) — on je primarni ključ u bazi.
class PersonScreen extends StatefulWidget {
  final String slug;

  const PersonScreen({super.key, required this.slug});

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  late Future<PersonHub?> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchWithMeta();
  }

  @override
  void didUpdateWidget(PersonScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      _future = _fetchWithMeta();
    }
  }

  /// Fetch + runtime <title>/og meta — isti format kao worker inject za /p/.
  Future<PersonHub?> _fetchWithMeta() async {
    final hub = await PersonService.fetch(widget.slug);
    if (hub != null && mounted) {
      setPageMeta(title: '${hub.name} — podcast profil – DOMOVINA.ai');
    }
    return hub;
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  /// Kopira javnu poveznicu na profil (`/p/<slug>`). Worker injecta osobno-
  /// specifične OG tagove na taj path (ime + broj epizoda/kanala) pa WhatsApp/
  /// Facebook preview pokaže osobu, ne generički domovina.ai — vidi web/_worker.js.
  void _shareProfile() {
    final url = 'https://domovina.ai/p/${widget.slug}';
    Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.personLinkCopied),
        duration: const Duration(seconds: 2),
      ),
    );
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
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: l.commonBack,
                    onPressed: _back,
                  ),
                  const Spacer(),
                  FutureBuilder<PersonHub?>(
                    future: _future,
                    builder: (context, snap) => IconButton(
                      icon: const Icon(Icons.ios_share),
                      tooltip: l.personShareTooltip,
                      // Aktivan tek kad profil postoji — nema smisla dijeliti 404.
                      onPressed: snap.data != null ? _shareProfile : null,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<PersonHub?>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final hub = snap.data;
                  if (hub == null) {
                    return _NotFound(slug: widget.slug);
                  }
                  return _PersonContent(hub: hub);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Prazno / 404 stanje
// ---------------------------------------------------------------------------

class _NotFound extends StatelessWidget {
  final String slug;

  const _NotFound({required this.slug});

  /// Čitljivo ime iz slug-a (dijakritika je izgubljena u fold-u, ali dovoljno
  /// informativno da korisnik zna KOJU osobu nismo našli).
  static String _readable(String slug) => slug
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined,
                size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              l.personNotFoundTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '»${_readable(slug)}«',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l.personNotFoundBody,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sadržaj profila
// ---------------------------------------------------------------------------

class _PersonContent extends StatelessWidget {
  final PersonHub hub;

  const _PersonContent({required this.hub});

  /// Iznad ove širine → dvostupčani layout (lijevo fiksni info, desno scroll
  /// epizode). Ispod → jedan stupac (mobitel).
  static const double _twoColBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoColBreakpoint) {
          return _SingleColumn(hub: hub);
        }
        return _TwoColumn(hub: hub);
      },
    );
  }
}

/// Mobitel / usko — sve u jednom scroll stupcu.
class _SingleColumn extends StatelessWidget {
  final PersonHub hub;

  const _SingleColumn({required this.hub});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Osoba bez gostovanja: kanali/timeline dolaze iz spomena (govor-agregacije
    // su prazne), a naslov sekcije kanala se mijenja u „Spominje se na".
    final mentionOnly = hub.isMentionOnly;
    final channels = mentionOnly ? hub.mentionChannels : hub.channels;
    final timeline = mentionOnly ? hub.mentionTimeline : hub.timeline;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            _Header(hub: hub),
            if (mentionOnly) ...[
              const SizedBox(height: 14),
              _MentionOnlyNote(text: l.personMentionOnlyNote),
            ],
            if (channels.isNotEmpty) ...[
              const SizedBox(height: 28),
              _ChannelsSection(
                channels: channels,
                title: mentionOnly ? l.personMentionedOn : l.personAppearsOn,
              ),
            ],
            if (timeline.length > 1) ...[
              const SizedBox(height: 28),
              _TimelineSection(timeline: timeline),
            ],
            if (hub.episodes.isNotEmpty) ...[
              const SizedBox(height: 28),
              _EpisodesSection(
                title: l.personEpisodesHeading,
                episodes: hub.episodes,
                personSlug: hub.slug,
              ),
            ],
            if (hub.mentions.isNotEmpty) ...[
              const SizedBox(height: 28),
              _EpisodesSection(
                title: l.personMentionedIn,
                episodes: hub.mentions,
                personSlug: hub.slug,
                isMention: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Desktop — lijevo fiksni info (header, kanali, timeline) koji ostaje vidljiv,
/// desno neovisno scrollabilna lista epizoda.
class _TwoColumn extends StatelessWidget {
  final PersonHub hub;

  const _TwoColumn({required this.hub});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasMentions = hub.mentions.isNotEmpty;
    final mentionOnly = hub.isMentionOnly;
    final channels = mentionOnly ? hub.mentionChannels : hub.channels;
    final timeline = mentionOnly ? hub.mentionTimeline : hub.timeline;
    // Treći stupac („Spominje se u") traži više širine da sve tri kolone dišu.
    // Bez gostovanja su stupca samo dva → uža, gušća kompozicija.
    final maxWidth = hasMentions && !mentionOnly ? 1440.0 : 1180.0;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lijevi stupac — glavni podaci; vlastiti scroll ako je visok.
            SizedBox(
              width: 380,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(hub: hub),
                    if (mentionOnly) ...[
                      const SizedBox(height: 14),
                      _MentionOnlyNote(text: l.personMentionOnlyNote),
                    ],
                    if (channels.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _ChannelsSection(
                        channels: channels,
                        title:
                            mentionOnly ? l.personMentionedOn : l.personAppearsOn,
                      ),
                    ],
                    if (timeline.length > 1) ...[
                      const SizedBox(height: 28),
                      _TimelineSection(timeline: timeline),
                    ],
                  ],
                ),
              ),
            ),
            // Srednji stupac — „Govori u" (epizode), neovisan scroll.
            if (hub.episodes.isNotEmpty)
              Expanded(
                flex: 3,
                child: _EpisodeListColumn(
                  title: l.personEpisodesHeading,
                  episodes: hub.episodes,
                  personSlug: hub.slug,
                ),
              ),
            // Desni stupac — „Spominje se u" (spomeni), zaseban scroll. Tanka
            // vertikalna linija razdvaja ga od „Govori u" radi preglednosti —
            // samo kad taj stupac postoji (osoba bez gostovanja ga nema).
            if (hasMentions) ...[
              if (hub.episodes.isNotEmpty)
                const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                flex: 2,
                child: _EpisodeListColumn(
                  title: l.personMentionedIn,
                  episodes: hub.mentions,
                  personSlug: hub.slug,
                  isMention: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PersonHub hub;

  const _Header({required this.hub});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    // „0 epizoda / 0 kanala" je šum na profilu osobe koja nikad nije gostovala —
    // govor-pilule se pokazuju samo kad govor postoji, a kanali se tada broje iz
    // spomena.
    final speaks = hub.episodes.isNotEmpty;
    final mentionChannelCount = hub.mentionChannels.length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Avatar(name: hub.name, avatarUrl: hub.avatarUrl),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hub.name,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (speaks) ...[
                    _StatPill(
                      icon: Icons.podcasts,
                      label: l.personEpisodesCount(hub.episodeCount),
                    ),
                    _StatPill(
                      icon: Icons.tv,
                      label: l.channelChannelsCount(hub.channelCount),
                    ),
                  ],
                  if (hub.mentions.isNotEmpty)
                    _StatPill(
                      icon: Icons.format_quote,
                      label: l.personMentionsCount(hub.mentionCount),
                    ),
                  if (!speaks && mentionChannelCount > 0)
                    _StatPill(
                      icon: Icons.tv,
                      label: l.channelChannelsCount(mentionChannelCount),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Napomena na profilu osobe koja se samo spominje — objašnjava zašto nema
/// popisa gostovanja, da prazan „Epizode" stupac ne izgleda kao greška.
class _MentionOnlyNote extends StatelessWidget {
  final String text;

  const _MentionOnlyNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.croBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.fromBorderSide(AppTheme.brandRim(theme.brightness)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;

  const _Avatar({required this.name, required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    const double size = 72;
    // Brand-fill navy (croBlue) + brandRim — NE cs.primary (M3 dark ga izblijedi).
    final initials = _initials(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.croBlue,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          AppTheme.brandRim(Theme.of(context).brightness),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: (avatarUrl != null && avatarUrl!.isNotEmpty)
          ? Image.network(
              avatarUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => _initialsLabel(initials),
            )
          : _initialsLabel(initials),
    );
  }

  Widget _initialsLabel(String initials) => Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 26,
        ),
      );

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.croBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.fromBorderSide(AppTheme.brandRim(theme.brightness)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Foreground/ikona = cs.primary (per brand pravilo), ne croBlue fill.
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Gostuje na" — raspodjela po kanalima
// ---------------------------------------------------------------------------

class _ChannelsSection extends StatelessWidget {
  final List<PersonChannelCount> channels;

  /// „Gostuje na" (govor) ili „Spominje se na" (osoba bez gostovanja).
  final String title;

  const _ChannelsSection({required this.channels, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: channels
              .map((c) => _ChannelChip(channel: c))
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _ChannelChip extends StatelessWidget {
  final PersonChannelCount channel;

  const _ChannelChip({required this.channel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = channel.channel.replaceAll('_', ' ');
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.go('/c/${channel.channelRouteSlug}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tv, size: 15, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${channel.count}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline — mjesečna aktivnost (jednostavan bar graf)
// ---------------------------------------------------------------------------

class _TimelineSection extends StatelessWidget {
  final List<PersonMonthCount> timeline;

  const _TimelineSection({required this.timeline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    // Popuni praznine (mjesece bez epizoda) da x-os bude LINEARNA po vremenu —
    // inače se mjeseci s podacima "zbiju" i osi se ne mogu vjerovati.
    final months = _expandMonths(timeline);
    if (months.length < 2) return const SizedBox.shrink();
    final maxCount = months.fold<int>(1, (m, e) => e.count > m ? e.count : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: l.personActivityOverTime),
        const SizedBox(height: 14),
        // Stupci popunjavaju punu širinu (svaki Expanded) → rubne oznake
        // (prvi/zadnji mjesec) se prirodno poravnaju s prvim/zadnjim stupcem.
        SizedBox(
          height: 68,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in months)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.8),
                    child: Tooltip(
                      message: '${m.month} · ${m.count}',
                      waitDuration: const Duration(milliseconds: 300),
                      child: Container(
                        height: m.count == 0
                            ? 3
                            : (7 + 55 * (m.count / maxCount)),
                        decoration: BoxDecoration(
                          color: m.count == 0
                              ? theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.14)
                              : AppTheme.croBlue.withValues(alpha: 0.72),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Tanka os-linija ispod stupaca.
        Container(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(months.first.month,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            Text(months.last.month,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

/// Pretvori rijetku listu mjeseci (samo oni s epizodama, "YYYY-MM") u
/// KONTINUIRANU listu od prvog do zadnjeg mjeseca, umećući `count: 0` za
/// praznine. Time timeline postaje istinita vremenska os.
List<PersonMonthCount> _expandMonths(List<PersonMonthCount> input) {
  if (input.isEmpty) return input;

  int? keyOf(String m) {
    final parts = m.split('-');
    if (parts.length < 2) return null;
    final y = int.tryParse(parts[0]);
    final mo = int.tryParse(parts[1]);
    if (y == null || mo == null) return null;
    return y * 12 + (mo - 1);
  }

  final counts = <int, int>{};
  int? minK, maxK;
  for (final e in input) {
    final k = keyOf(e.month);
    if (k == null) continue;
    counts[k] = e.count;
    if (minK == null || k < minK) minK = k;
    if (maxK == null || k > maxK) maxK = k;
  }
  if (minK == null || maxK == null) return input;

  final out = <PersonMonthCount>[];
  for (int k = minK; k <= maxK; k++) {
    final y = k ~/ 12;
    final mo = (k % 12) + 1;
    final label = '$y-${mo.toString().padLeft(2, '0')}';
    out.add(PersonMonthCount(month: label, count: counts[k] ?? 0));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Popis epizoda
// ---------------------------------------------------------------------------

class _EpisodesSection extends StatelessWidget {
  final String title;
  final List<PersonEpisode> episodes;

  /// Slug osobe — prosljeđuje se kao `?p=` na episode deep-link da episode
  /// ekran označi sekciju gdje osoba govori ("X govori ovdje" marker).
  final String personSlug;

  /// Popis spomena (ne gostovanja) → kartice nose oznaku trenutka.
  final bool isMention;

  const _EpisodesSection({
    required this.title,
    required this.episodes,
    required this.personSlug,
    this.isMention = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title),
        const SizedBox(height: 10),
        for (final e in episodes)
          _EpisodeCard(
            episode: e,
            personSlug: personSlug,
            isMention: isMention,
          ),
      ],
    );
  }
}

/// Desktop stupac: naslov + neovisno scrollabilna lista epizoda (lazy).
/// Koristi ga i „Govori u" (episodes) i „Spominje se u" (mentions) stupac.
class _EpisodeListColumn extends StatelessWidget {
  final String title;
  final List<PersonEpisode> episodes;

  /// Slug osobe — prosljeđuje se kao `?p=` na episode deep-link (marker).
  final String personSlug;

  /// Popis spomena (ne gostovanja) → kartice nose oznaku trenutka.
  final bool isMention;

  const _EpisodeListColumn({
    required this.title,
    required this.episodes,
    required this.personSlug,
    this.isMention = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      itemCount: episodes.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SectionTitle(title: title),
          );
        }
        return _EpisodeCard(
          episode: episodes[i - 1],
          personSlug: personSlug,
          isMention: isMention,
        );
      },
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final PersonEpisode episode;

  /// Slug osobe — appenda se kao `?p=` na deep-link da episode ekran prikaže
  /// "X govori ovdje" marker na ciljanoj sekciji članka.
  final String personSlug;

  /// Kartica je u popisu „Spominje se u" → prikaži je li spomen vezan uz TOČAN
  /// trenutak (tap seeka onamo) ili je samo epizodni (tap otvara od početka).
  /// Kod govor-epizoda razlika ne postoji — `first_ts` je uvijek stvaran.
  final bool isMention;

  const _EpisodeCard({
    required this.episode,
    required this.personSlug,
    this.isMention = false,
  });

  /// Sekunde → "16:45" / "1:05:30" (sat samo kad postoji).
  static String _clock(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final title = (episode.title != null && episode.title!.trim().isNotEmpty)
        ? episode.title!.trim()
        : episode.youtubeId;
    final channelName = episode.channel.replaceAll('_', ' ');
    final hasMoment = episode.firstTs > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('${episode.routePath}?p=$personSlug'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  CdnConfig.thumbnailUrl(episode.youtubeId),
                  width: 120,
                  height: 68,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(
                    width: 120,
                    height: 68,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.ondemand_video,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (isMention)
                          _MentionMomentChip(
                            hasMoment: hasMoment,
                            label: hasMoment
                                ? l.personMentionAtTime(
                                    _clock(episode.firstTs))
                                : l.personMentionWholeEpisode,
                          ),
                        _MetaChip(icon: Icons.tv, text: channelName),
                        if (episode.uploadDate.isNotEmpty)
                          _MetaChip(
                              icon: Icons.calendar_today,
                              text: episode.uploadDate),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Razlikuje dvije vrste spomena u popisu „Spominje se u".
///
/// Puna brand-crvena (`cs.tertiary`) = znamo TOČAN trenutak; tap seeka onamo i
/// ondje dočeka isti crveni marker u članku — namjerno ista boja da korisnik
/// poveže karticu i marker. Obrubljena/prigušena = trenutak nije razriješen iz
/// `article.json` (~40% spomena), pa tap otvara epizodu od početka.
class _MentionMomentChip extends StatelessWidget {
  final bool hasMoment;
  final String label;

  const _MentionMomentChip({required this.hasMoment, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = hasMoment ? Colors.white : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: hasMoment ? theme.colorScheme.tertiary : null,
        borderRadius: BorderRadius.circular(6),
        border: hasMoment
            ? null
            : Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(hasMoment ? Icons.play_arrow : Icons.subject, size: 12, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: hasMoment ? FontWeight.bold : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
