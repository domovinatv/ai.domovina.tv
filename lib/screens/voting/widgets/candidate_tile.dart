/// Kartica kandidata na ljestvici `/glasanje`.
///
/// Plan: `docs/plans/2026-08-08-glasanje-o-kanalima.md` §7.1 (neto rang), §8.2,
/// §8.4 (avatari).
///
/// Avatar ide isključivo kroz [CachedThumbnail] s **CDN-a**
/// (`cdn.domovina.ai/registry/avatars/<slug>.jpg`) — nikad izravno s YouTubea,
/// gdje CORS puca (isto pravilo kao `CdnConfig.thumbnailUrl`). Kandidat bez
/// avatara dobiva monogram na `AppTheme.croBlue` + `brandRim()`.
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/vote_candidate.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/cached_thumbnail.dart';

/// Što kartica nudi kao radnju.
enum CandidateActionMode {
  /// Bez ijednog akcijskog gumba — gost/neverificiran gleda ljestvicu.
  ///
  /// U ovom krugu ovdje **ne** stoji `⚑ Prati` iz §8.2: `candidate_follows` UI
  /// je Van opsega, a gumb koji ništa ne sprema je gori od nikakvog.
  none,

  /// 👍 / 👎 aktivni.
  vote,

  /// Glas je za danas potrošen — cijela lista je read-only.
  spent,
}

class CandidateTile extends StatelessWidget {
  final VoteCandidate candidate;
  final CandidateActionMode mode;

  /// Smjer glasa koji je korisnik danas dao **ovom** kandidatu (`1` / `-1`),
  /// `null` ako je glasao za nekog drugog ili nije glasao.
  final int? mojGlas;

  /// `1` = 👍, `-1` = 👎.
  final ValueChanged<int>? onVote;
  final VoidCallback? onOpen;

  const CandidateTile({
    super.key,
    required this.candidate,
    this.mode = CandidateActionMode.none,
    this.mojGlas,
    this.onVote,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (candidate.rank != null) ...[
              SizedBox(
                width: 26,
                child: Text(
                  '${candidate.rank}.',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            CandidateAvatar(candidate: candidate, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    candidate.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _podnaslov(l),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (candidate.status != VoteCandidateStatus.candidate) ...[
                    const SizedBox(height: 4),
                    _StatusBadge(status: candidate.status),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _NetScore(candidate: candidate),
            const SizedBox(width: 4),
            _Actions(
              mode: mode,
              mojGlas: mojGlas,
              votable: candidate.isVotable,
              onVote: onVote,
            ),
          ],
        ),
      ),
    );
  }

  String _podnaslov(AppLocalizations l) {
    final dijelovi = <String>[
      if (candidate.tags.isNotEmpty) candidate.tags.first,
      if (candidate.subscribers != null && candidate.subscribers! > 0)
        l.votingSubscribers(compactCount(candidate.subscribers!, l)),
      if (candidate.voditelji.isNotEmpty) candidate.voditelji.take(2).join(', '),
    ];
    return dijelovi.join(' · ');
  }
}

/// `400000` → „400 tis.", `1200000` → „1,2 mil.".
///
/// Sufiks je lokaliziran (ARB), a decimalni zarez dolazi iz istog ključa —
/// bez `intl` `NumberFormat`, koji bi tražio locale podatke (isti dug kao
/// datumi u `founder_booking.dart`).
String compactCount(int n, AppLocalizations l) {
  if (n >= 1000000) {
    final m = n / 1000000;
    final zapis = m >= 10 ? m.round().toString() : m.toStringAsFixed(1);
    return l.votingCountMillions(zapis);
  }
  if (n >= 1000) return l.votingCountThousands((n / 1000).round().toString());
  return '$n';
}

/// Avatar s CDN-a; bez njega monogram na brand navy podlozi.
class CandidateAvatar extends StatelessWidget {
  final VoteCandidate candidate;
  final double size;

  const CandidateAvatar({
    super.key,
    required this.candidate,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = candidate.avatarUrl;
    final radius = BorderRadius.circular(size / 4);

    if (url == null || url.isEmpty) {
      return _Monogram(
        name: candidate.displayName,
        size: size,
        radius: radius,
        brightness: theme.brightness,
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: CachedThumbnail(
        url: url,
        width: size,
        height: size,
        errorIcon: Icons.podcasts_outlined,
        errorIconSize: size * 0.5,
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  final String name;
  final double size;
  final BorderRadius radius;
  final Brightness brightness;

  const _Monogram({
    required this.name,
    required this.size,
    required this.radius,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    // Zagrade u nazivu su alias („Rebootcast (Reboot magazine)") — bez rezanja
    // bi monogram uzeo `(` kao drugo slovo.
    final slova = name
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^\p{L}]', unicode: true), ''))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Brand navy fill + rim (theme_and_view_mode_ux pravilo).
        color: AppTheme.croBlue,
        borderRadius: radius,
        border: Border.fromBorderSide(AppTheme.brandRim(brightness)),
      ),
      child: Text(
        slova.isEmpty ? '?' : slova,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
        ),
      ),
    );
  }
}

/// Neto rezultat (👍 − 👎) — jedina brojka po kojoj se rangira (§7.1).
class _NetScore extends StatelessWidget {
  final VoteCandidate candidate;

  const _NetScore({required this.candidate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final net = candidate.net;
    final boja = net > 0
        ? AppTheme.croBlue
        : (net < 0 ? AppTheme.croRed : theme.colorScheme.onSurfaceVariant);

    return Semantics(
      label: l.votingNetLabel(net),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            net > 0 ? '+$net' : '$net',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: boja,
            ),
          ),
          Text(
            l.votingVotesCount(candidate.totalVotes),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final CandidateActionMode mode;
  final int? mojGlas;
  final bool votable;
  final ValueChanged<int>? onVote;

  const _Actions({
    required this.mode,
    required this.mojGlas,
    required this.votable,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    if (mojGlas != null) {
      final gore = mojGlas! > 0;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.croBlue,
          borderRadius: BorderRadius.circular(20),
          border: Border.fromBorderSide(AppTheme.brandRim(theme.brightness)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(gore ? Icons.thumb_up : Icons.thumb_down,
                size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              l.votingYourVoteToday,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (mode == CandidateActionMode.none) return const SizedBox.shrink();

    final aktivno = mode == CandidateActionMode.vote && votable;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: aktivno ? () => onVote?.call(kVoteDirectionUp) : null,
          icon: const Icon(Icons.thumb_up_outlined, size: 20),
          tooltip: l.votingVoteUp,
          visualDensity: VisualDensity.compact,
          color: AppTheme.croBlue,
        ),
        IconButton(
          onPressed: aktivno ? () => onVote?.call(kVoteDirectionDown) : null,
          icon: const Icon(Icons.thumb_down_outlined, size: 20),
          tooltip: l.votingVoteDown,
          visualDensity: VisualDensity.compact,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final VoteCandidateStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final tekst = switch (status) {
      VoteCandidateStatus.winner => l.votingStatusWinner,
      VoteCandidateStatus.onboarding => l.votingStatusOnboarding,
      VoteCandidateStatus.onboarded => l.votingStatusOnboarded,
      VoteCandidateStatus.withdrawn => l.votingStatusWithdrawn,
      _ => '',
    };
    if (tekst.isEmpty) return const SizedBox.shrink();

    final istaknuto = status == VoteCandidateStatus.winner;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: istaknuto
            ? AppTheme.croRed.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tekst,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: istaknuto ? AppTheme.croRed : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
