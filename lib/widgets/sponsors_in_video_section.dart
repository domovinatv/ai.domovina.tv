import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/sponsors_in_video.dart';
import '../services/open_url.dart';
import '../theme/app_theme.dart';

/// Sekcija „Uz podršku" — sponzori UGRAĐENI u snimku (vidi [SponsorsInVideo]).
///
/// Ton je zahvala partneru koji je omogućio epizodu, ne reklama: kartica nosi
/// ime, ulogu, autorov opis i poveznice, a pouzdan raspon u snimci dobiva gumb
/// „Poslušaj" koji pušta točno taj dio i sam stane (zaustavljanje radi ekran,
/// koji drži player). Nepouzdani rasponi (zahvala, poglavlje) su samo skok na
/// trenutak, bez zaustavljanja.
///
/// Nije isto što i buduća DINAMIČKA sponzorstva kupljena na domovina.ai — ta
/// dolaze kao zaseban sloj s vlastitim widgetom.
///
/// Bez imenovanog sponzora (404, `sponsors: []`, samo `_unattributed`) ne
/// zauzima ništa.
class SponsorsInVideoSection extends StatelessWidget {
  final SponsorsInVideo? data;

  /// Pusti segment od `start` i zaustavi na `end`. Null dok player nije
  /// spreman — gumbi su tada onemogućeni (isto kao play u članku).
  final void Function(SponsorInVideoSegment segment)? onListen;

  /// Skoči na trenutak i nastavi reprodukciju bez zaustavljanja.
  final void Function(SponsorInVideoSegment segment)? onJump;

  /// Unutarnji rub sekcije — standardni layout ga daje sam (20), osnovni
  /// layout već ima vanjski padding 16 pa ovdje traži 0.
  final double horizontalPadding;

  const SponsorsInVideoSection({
    super.key,
    required this.data,
    this.onListen,
    this.onJump,
    this.horizontalPadding = 20,
  });

  @override
  Widget build(BuildContext context) {
    final named = data?.named ?? const <SponsorInVideo>[];
    if (named.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    final partners = [
      for (final s in named)
        if (!s.role.isCredit) s,
    ];
    final credits = [
      for (final s in named)
        if (s.role.isCredit) s,
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        16,
        horizontalPadding,
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.volunteer_activism_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                l.sponsorsInVideoTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.sponsorsInVideoIntro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final s in partners)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SponsorCard(
                sponsor: s,
                onListen: onListen,
                onJump: onJump,
              ),
            ),
          if (credits.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: partners.isEmpty ? 0 : 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final c in credits) _CreditRow(sponsor: c)],
              ),
            ),
        ],
      ),
    );
  }
}

String sponsorRoleLabel(SponsorInVideoRole role, AppLocalizations l) =>
    switch (role) {
      SponsorInVideoRole.sponsor => l.sponsorsInVideoRoleSponsor,
      SponsorInVideoRole.partner => l.sponsorsInVideoRolePartner,
      SponsorInVideoRole.wardrobe => l.sponsorsInVideoRoleWardrobe,
      SponsorInVideoRole.studio => l.sponsorsInVideoRoleStudio,
      SponsorInVideoRole.other => l.sponsorsInVideoRoleOther,
    };

/// `1:39:23` / `57:48` — isti format kao ostatak ekrana epizode.
String formatSponsorClock(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String p(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${p(m)}:${p(s)}' : '$m:${p(s)}';
}

class _SponsorCard extends StatelessWidget {
  final SponsorInVideo sponsor;
  final void Function(SponsorInVideoSegment segment)? onListen;
  final void Function(SponsorInVideoSegment segment)? onJump;

  const _SponsorCard({required this.sponsor, this.onListen, this.onJump});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.fromBorderSide(AppTheme.brandRim(theme.brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sponsor.name!,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sponsorRoleLabel(sponsor.role, l),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (sponsor.blurb != null) ...[
            const SizedBox(height: 8),
            _ExpandableBlurb(text: sponsor.blurb!),
          ],
          if (sponsor.segments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final seg in sponsor.segments)
                  seg.playable
                      ? _ListenButton(
                          segment: seg,
                          onPressed: onListen == null
                              ? null
                              : () => onListen!(seg),
                        )
                      : _JumpLink(
                          segment: seg,
                          onPressed: onJump == null ? null : () => onJump!(seg),
                        ),
              ],
            ),
          ],
          _SponsorLinks(sponsor: sponsor),
        ],
      ),
    );
  }
}

class _ListenButton extends StatelessWidget {
  final SponsorInVideoSegment segment;
  final VoidCallback? onPressed;

  const _ListenButton({required this.segment, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = segment.kind == SponsorInVideoKind.rubric
        ? l.sponsorsInVideoListenRubric
        : l.sponsorsInVideoListen;
    final range =
        '${formatSponsorClock(segment.start)}–${formatSponsorClock(segment.end)}';
    return Tooltip(
      message: range,
      child: FilledButton.tonalIcon(
        icon: const Icon(Icons.play_arrow, size: 18),
        label: Text('$label · ${formatSponsorClock(segment.durationSeconds)}'),
        onPressed: onPressed,
      ),
    );
  }
}

class _JumpLink extends StatelessWidget {
  final SponsorInVideoSegment segment;
  final VoidCallback? onPressed;

  const _JumpLink({required this.segment, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final time = formatSponsorClock(segment.start);
    final label = switch (segment.kind) {
      SponsorInVideoKind.mention => l.sponsorsInVideoThanksAt(time),
      SponsorInVideoKind.chapter => l.sponsorsInVideoChapterAt(time),
      _ => l.sponsorsInVideoAt(time),
    };
    return TextButton.icon(
      icon: const Icon(Icons.schedule, size: 16),
      label: Text(label),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

class _SponsorLinks extends StatelessWidget {
  final SponsorInVideo sponsor;

  const _SponsorLinks({required this.sponsor});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final url = sponsor.url;
    final ig = sponsor.instagram;
    if (url == null && ig == null) return const SizedBox.shrink();
    final style = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        children: [
          if (url != null)
            TextButton.icon(
              style: style,
              icon: const Icon(Icons.language, size: 16),
              label: Text(_hostOf(url) ?? l.sponsorsInVideoWebsite),
              onPressed: () => openUrl(url),
            ),
          if (ig != null)
            TextButton.icon(
              style: style,
              icon: const Icon(Icons.photo_camera_outlined, size: 16),
              label: const Text('Instagram'),
              onPressed: () => openUrl(ig),
            ),
        ],
      ),
    );
  }
}

/// `https://www.plazma.rs/` → `plazma.rs` — čitljivija oznaka od „Web".
String? _hostOf(String url) {
  final host = Uri.tryParse(url)?.host;
  if (host == null || host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Garderoba / studio: jedan redak zahvale, bez kartice i bez segmenata.
class _CreditRow extends StatelessWidget {
  final SponsorInVideo sponsor;

  const _CreditRow({required this.sponsor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final link = sponsor.url ?? sponsor.instagram;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('${sponsorRoleLabel(sponsor.role, l)}: ', style: muted),
          if (link != null)
            InkWell(
              onTap: () => openUrl(link),
              child: Text(
                sponsor.name!,
                style: muted?.copyWith(
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            )
          else
            Text(
              sponsor.name!,
              style: muted?.copyWith(fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

class _ExpandableBlurb extends StatefulWidget {
  final String text;

  const _ExpandableBlurb({required this.text});

  @override
  State<_ExpandableBlurb> createState() => _ExpandableBlurbState();
}

class _ExpandableBlurbState extends State<_ExpandableBlurb> {
  static const _collapsedLines = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.4,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : _collapsedLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows)
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _expanded ? l.sponsorsInVideoLess : l.sponsorsInVideoMore,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Sažeti ulaz u sponzore u panelu playera (desni stupac na desktopu, ladica
/// na mobitelu). Sekcija [SponsorsInVideoSection] stoji iza sažetka, ~1500 px
/// ispod vrha — a deep-link (`/v/<id>/t/<sec>`) na mobitelu odmah otvori
/// ladicu s playerom preko svega. Bez ove trake gumb „Poslušaj" korisnik
/// nije mogao naći (prijava 24.9.2026. na `aue1GuuMsbA/t/8`).
///
/// Jedan gumb po pouzdanom rasponu; isti raspon pripisan dvama sponzorima
/// (`NwLeHiokKSU`: HiPP i Plazma) postaje jedan gumb s oba imena. Imenovani
/// sponzori bez takvog raspona ostaju samo navedeni. Krediti (garderoba,
/// studio) ovdje ne ulaze — žive u sekciji.
class SponsorsInVideoPlayerStrip extends StatelessWidget {
  final SponsorsInVideo? data;
  final void Function(SponsorInVideoSegment segment)? onListen;

  const SponsorsInVideoPlayerStrip({
    super.key,
    required this.data,
    this.onListen,
  });

  @override
  Widget build(BuildContext context) {
    final partners = [
      for (final s in data?.named ?? const <SponsorInVideo>[])
        if (!s.role.isCredit) s,
    ];
    if (partners.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    // (start, end) → segment + imena sponzora kojima pripada.
    final clips = <(int, int), (SponsorInVideoSegment, List<String>)>{};
    final silent = <String>[];
    for (final s in partners) {
      final playable = s.playableSegments;
      if (playable.isEmpty) {
        silent.add(s.name!);
        continue;
      }
      for (final seg in playable) {
        final entry = clips.putIfAbsent((seg.start, seg.end), () => (seg, []));
        entry.$2.add(s.name!);
      }
    }
    final ordered = clips.values.toList()
      ..sort((a, b) => a.$1.start.compareTo(b.$1.start));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.volunteer_activism_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  silent.isEmpty
                      ? l.sponsorsInVideoTitle
                      : '${l.sponsorsInVideoTitle}: ${silent.join(', ')}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          if (ordered.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (seg, names) in ordered)
                  Tooltip(
                    message: seg.kind == SponsorInVideoKind.rubric
                        ? l.sponsorsInVideoListenRubric
                        : l.sponsorsInVideoListen,
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: Text(
                        '${names.join(', ')} · '
                        '${formatSponsorClock(seg.durationSeconds)}',
                      ),
                      onPressed: onListen == null ? null : () => onListen!(seg),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
