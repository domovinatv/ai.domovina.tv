library;

import 'package:flutter/material.dart';

import '../models/pinka_campaign.dart';
import '../models/pinka_public_contribution.dart';
import '../pinka_client.dart';
import '../pinka_config.dart';
import '../util/pinka_money.dart';

/// Kompaktna "Zid podrške" kartica za umetanje na channel/episode ekran.
///
/// Sama se učita i **sakrije (SizedBox.shrink) ako subjekt nema aktivnu
/// kampanju** — pa je sigurno staviti bilo gdje. Tap → [onOpen] (host navigira
/// na pun [PinkaCampaignScreen]). Prikazuje progres, broj podržavatelja i mali
/// pregled zadnjih donatora.
class PinkaSupportCard extends StatefulWidget {
  final String subjectType;
  final List<String> subjectRefs;
  final PinkaClient client;
  final PinkaConfig config;

  /// Pozvano kad korisnik želi otvoriti pun ekran podrške.
  final void Function(PinkaCampaign campaign) onOpen;

  /// Koliko zadnjih donatora prikazati u pregledu (0 = nijednog).
  final int previewCount;

  PinkaSupportCard({
    super.key,
    required this.subjectType,
    required this.subjectRefs,
    required this.onOpen,
    PinkaClient? client,
    this.config = PinkaConfig.defaults,
    this.previewCount = 3,
  }) : client = client ?? PinkaClient.instance;

  /// Kanal: subject_ref = UC… id ILI domovina interni channel id.
  PinkaSupportCard.channel({
    Key? key,
    required String channelId,
    String? youtubeChannelId,
    required void Function(PinkaCampaign campaign) onOpen,
    PinkaClient? client,
    PinkaConfig config = PinkaConfig.defaults,
    int previewCount = 3,
  }) : this(
          key: key,
          subjectType: PinkaSubject.channel,
          subjectRefs: [channelId, ?youtubeChannelId],
          onOpen: onOpen,
          client: client,
          config: config,
          previewCount: previewCount,
        );

  @override
  State<PinkaSupportCard> createState() => _PinkaSupportCardState();
}

class _PinkaSupportCardState extends State<PinkaSupportCard> {
  PinkaCampaign? _campaign;
  List<PinkaPublicContribution> _preview = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await widget.client.campaignForSubject(
      subjectType: widget.subjectType,
      subjectRefs: widget.subjectRefs,
    );
    List<PinkaPublicContribution> preview = const [];
    if (c != null && widget.previewCount > 0) {
      preview = await widget.client.wall(c.id, limit: widget.previewCount);
    }
    if (!mounted) return;
    setState(() {
      _campaign = c;
      _preview = preview;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _campaign;
    if (!_loaded || c == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onOpen(c),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.volunteer_activism,
                        color: theme.colorScheme.tertiary, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Zid podrške',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Icon(Icons.chevron_right,
                        color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 10),
                if (c.hasGoal) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: c.progress,
                      minHeight: 8,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Prikupljeno ${fmtEur(c.totalRaisedCents)} € '
                    'od ${fmtEur(c.goalCents!)} € · '
                    '${c.contributorCount} podržavatelja',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ] else
                  Text(
                    'Prikupljeno ${fmtEur(c.totalRaisedCents)} € · '
                    '${c.contributorCount} podržavatelja',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                if (_preview.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in _preview)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          label: Text(
                            '${p.displayNameOrAnon} · ${fmtEur(p.amountCents)} €',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => widget.onOpen(c),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.tertiary,
                      foregroundColor: theme.colorScheme.onTertiary,
                    ),
                    icon: const Icon(Icons.favorite, size: 18),
                    label: const Text('Podrži'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
