library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../models/pinka_campaign.dart';
import '../pinka_client.dart';
import '../pinka_config.dart';
import '../util/pinka_money.dart';

/// Uvijek-vidljiva ("sticky") traka Zida podrške za dno ekrana.
///
/// Kompaktni pandan [PinkaSupportCard]-u: ista logika učitavanja i isto
/// **auto-skrivanje (SizedBox.shrink) ako subjekt nema aktivnu kampanju**, ali
/// stane u ~56 px i namijenjena je `Scaffold.bottomNavigationBar`-u (sama ili
/// složena iznad postojeće navigacije) pa CTA ostaje na ekranu bez obzira na
/// scroll. Tap bilo gdje po traci → [onOpen].
///
/// [applyBottomSafeArea] uključi kad je traka *zadnji* element na dnu (inače
/// donja navigacija ispod nje već troši safe area i dobio bi dupli razmak).
///
/// Za razliku od kartice, traka podržava **fallback subjekt**: epizoda bez
/// vlastite kampanje pokazuje kampanju svog kanala (većina epizoda nema
/// per-epizoda kampanju, a CTA mora ostati vidljiv). [onOpen] tada dobije
/// `viaFallback: true` pa host može navigirati na channel rutu podrške.
class PinkaSupportBar extends StatefulWidget {
  final String subjectType;
  final List<String> subjectRefs;

  /// Subjekt koji se pokušava ako primarni nema aktivnu kampanju (prazno = bez).
  final String? fallbackSubjectType;
  final List<String> fallbackSubjectRefs;

  final PinkaClient client;
  final PinkaConfig config;

  /// Pozvano kad korisnik želi otvoriti pun ekran podrške. `viaFallback` je
  /// true kad prikazana kampanja dolazi od fallback subjekta (npr. kanal).
  final void Function(PinkaCampaign campaign, bool viaFallback) onOpen;

  /// Traka je najniži element na ekranu → sama respektira donji notch/gestu.
  final bool applyBottomSafeArea;

  PinkaSupportBar({
    super.key,
    required this.subjectType,
    required this.subjectRefs,
    required this.onOpen,
    this.fallbackSubjectType,
    this.fallbackSubjectRefs = const [],
    this.applyBottomSafeArea = true,
    PinkaClient? client,
    this.config = PinkaConfig.defaults,
  }) : client = client ?? PinkaClient.instance;

  /// Kanal: subject_ref = UC… id ILI domovina interni channel id.
  PinkaSupportBar.channel({
    Key? key,
    required String channelId,
    String? youtubeChannelId,
    required void Function(PinkaCampaign campaign, bool viaFallback) onOpen,
    bool applyBottomSafeArea = true,
    PinkaClient? client,
    PinkaConfig config = PinkaConfig.defaults,
  }) : this(
          key: key,
          subjectType: PinkaSubject.channel,
          subjectRefs: [channelId, ?youtubeChannelId],
          onOpen: onOpen,
          applyBottomSafeArea: applyBottomSafeArea,
          client: client,
          config: config,
        );

  /// Epizoda: subject_ref = YouTube video id. [channelRefs] (UC… id i/ili
  /// interni channel id) su fallback kad epizoda nema vlastitu kampanju.
  PinkaSupportBar.episode({
    Key? key,
    required String youtubeId,
    required void Function(PinkaCampaign campaign, bool viaFallback) onOpen,
    List<String> channelRefs = const [],
    bool applyBottomSafeArea = true,
    PinkaClient? client,
    PinkaConfig config = PinkaConfig.defaults,
  }) : this(
          key: key,
          subjectType: PinkaSubject.episode,
          subjectRefs: [youtubeId],
          fallbackSubjectType:
              channelRefs.isEmpty ? null : PinkaSubject.channel,
          fallbackSubjectRefs: channelRefs,
          onOpen: onOpen,
          applyBottomSafeArea: applyBottomSafeArea,
          client: client,
          config: config,
        );

  @override
  State<PinkaSupportBar> createState() => _PinkaSupportBarState();
}

class _PinkaSupportBarState extends State<PinkaSupportBar> {
  PinkaCampaign? _campaign;
  bool _viaFallback = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PinkaSupportBar old) {
    super.didUpdateWidget(old);
    // Host može razriješiti channel refs tek nakon prvog framea (index se
    // učitava lazy) — tada ponovo probaj.
    if (old.fallbackSubjectRefs.join(',') !=
            widget.fallbackSubjectRefs.join(',') ||
        old.subjectRefs.join(',') != widget.subjectRefs.join(',')) {
      _load();
    }
  }

  Future<void> _load() async {
    var c = await widget.client.campaignForSubject(
      subjectType: widget.subjectType,
      subjectRefs: widget.subjectRefs,
    );
    var viaFallback = false;
    final fbType = widget.fallbackSubjectType;
    if (c == null && fbType != null && widget.fallbackSubjectRefs.isNotEmpty) {
      c = await widget.client.campaignForSubject(
        subjectType: fbType,
        subjectRefs: widget.fallbackSubjectRefs,
      );
      viaFallback = c != null;
    }
    if (!mounted) return;
    setState(() {
      _campaign = c;
      _viaFallback = viaFallback;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _campaign;
    if (!_loaded || c == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);

    // Uski ekrani: naslov "Zid podrške" pada van, ostaje samo iznos + CTA.
    final narrow = MediaQuery.sizeOf(context).width < 420;

    final status = c.hasGoal
        ? '${l.pinkaRaisedOfGoal(fmtEur(c.totalRaisedCents), fmtEur(c.goalCents!))}'
            ' · ${l.pinkaSupportersCount(c.contributorCount)}'
        : '${l.pinkaRaised(fmtEur(c.totalRaisedCents))}'
            ' · ${l.pinkaSupportersCount(c.contributorCount)}';

    return Material(
      color: cs.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        bottom: widget.applyBottomSafeArea,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: InkWell(
            onTap: () => widget.onOpen(c, _viaFallback),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.hasGoal)
                  LinearProgressIndicator(
                    value: c.progress,
                    minHeight: 3,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: cs.tertiary,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                  child: Row(
                    children: [
                      Icon(Icons.volunteer_activism,
                          color: cs.tertiary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!narrow)
                              Text(
                                // Fallback (kampanja kanala) → njen naslov je
                                // informativniji od generičnog "Zid podrške".
                                _viaFallback ? c.title : l.pinkaWallTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () => widget.onOpen(c, _viaFallback),
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.tertiary,
                          foregroundColor: cs.onTertiary,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        icon: const Icon(Icons.favorite, size: 18),
                        label: Text(l.pinkaSupport),
                      ),
                    ],
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
