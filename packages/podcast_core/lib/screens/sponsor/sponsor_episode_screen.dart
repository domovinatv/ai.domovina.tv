import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../src/log.dart' show log;
import '../../models/channel_detail.dart';
import '../../models/sponsor_offer.dart';
import '../../models/sponsor_topic.dart';
import '../../onboarding/ui/auth_sheet.dart';
import '../../pinka_sdk/pinka_sdk.dart';
import '../../router/nav.dart';
import '../../services/auth_service.dart';
import '../../services/channel_cache.dart';
import '../../services/sponsored_moments_service.dart';
import '../../services/url_sync.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sponsor_timeline_bar.dart';
import '../../widgets/sponsors_in_video_section.dart' show formatSponsorClock;
import 'sponsor_checkout_form.dart';
import 'sponsor_store_screen.dart' show sponsorTopicLabel;

/// Karta sponzorskih trenutaka jedne epizode — `/v/:id/sponzoriraj`.
///
/// Jedan ekran, četiri faze: karta → forma → plaćanje (SEPA) → stanje
/// narudžbe. Namjerno bez zasebnih ruta po fazi: hold, intent i forma žive
/// u ovom `State`-u, a Back iz plaćanja ne smije tiho baciti rezervaciju.
/// Jedina vanjska ulazna točka u kasniju fazu je `?narudzba=<id>` — kupac
/// se preko te poveznice vraća na stanje narudžbe (i brojke, kad mjerenje
/// stigne).
class SponsorEpisodeScreen extends StatefulWidget {
  final String youtubeId;

  /// `?narudzba=<contribution_id>` — otvori izravno stanje narudžbe.
  final String? orderId;

  const SponsorEpisodeScreen({
    super.key,
    required this.youtubeId,
    this.orderId,
  });

  @override
  State<SponsorEpisodeScreen> createState() => _SponsorEpisodeScreenState();
}

enum _Phase { map, form, pay, status }

class _SponsorEpisodeScreenState extends State<SponsorEpisodeScreen> {
  // MVP ima jednu kampanju (ugovor O1). Kad ih bude više, kampanja se
  // razrješava po kanalu epizode.
  final SponsorCampaign _campaign = SponsorCampaign.domovinaTv;

  _Phase _phase = _Phase.map;
  List<SponsorOffer>? _offers;
  ChannelVideo? _video;
  bool _loadFailed = false;

  SponsorOffer? _selected;
  final _formData = SponsorCheckoutFormData();
  bool _submitting = false;
  String? _formError;

  PinkaContributionIntent? _intent;
  String? _orderId;
  SponsorOrderStatus? _status;
  bool _statusMissing = false;
  Timer? _pollTimer;
  Timer? _clockTimer;

  /// Uzastopni prazni odgovori statusa — nepostojeća narudžba ne smije
  /// zauvijek pollati svakih 5 s.
  int _missingTicks = 0;

  /// Tickovi nakon `paid` dok se čeka broj računa (izdaje se asinkrono).
  int _invoiceTicks = 0;

  @override
  void initState() {
    super.initState();
    _loadEpisode();
    if (widget.orderId != null) {
      _orderId = widget.orderId;
      _phase = _Phase.status;
      _startPolling();
    } else {
      _loadOffers();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _formData.dispose();
    super.dispose();
  }

  Future<void> _loadEpisode() async {
    try {
      final detail =
          await channelCache.loadChannelWithText(_campaign.channelId);
      final v = detail.videos.where((v) => v.id == widget.youtubeId);
      if (mounted && v.isNotEmpty) setState(() => _video = v.first);
    } catch (e) {
      log('SponsorMap: channel load failed — $e');
    }
  }

  Future<void> _loadOffers() async {
    setState(() => _loadFailed = false);
    try {
      final offers = await SponsoredMomentsService.instance.loadOffers(
        _campaign,
        youtubeId: widget.youtubeId,
      );
      if (!mounted) return;
      setState(() {
        _offers = offers;
        // Odabrani trenutak više nije slobodan (osvježenje nakon 409).
        if (_selected != null &&
            !offers.any(
              (o) => o.slotKey == _selected!.slotKey && o.state.isBuyable,
            )) {
          _selected = null;
        }
      });
    } catch (e) {
      log('SponsorMap: offers load failed — $e');
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  // ── checkout ───────────────────────────────────────────────────────────
  Future<void> _submit(SponsorCheckoutDraft draft) async {
    final offer = _selected;
    if (offer == null) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _submitting = true;
      _formError = null;
    });
    final client = PinkaClient.instance;
    // Sesija je mogla nestati između odabira trenutka i slanja forme. Forma
    // živi u `_formData` i preživi prijavu unutar sheeta (OTP, passkey);
    // web OAuth je full-page redirect i nju NE preživi — zato `_pick` traži
    // prijavu prije forme, a ovo je samo osigurač.
    if (!AuthService.instance.isSignedIn && !await _signIn()) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _formError = l.sponsorSignInRequired;
        });
      }
      return;
    }
    try {
      var order = draft.order;
      final logo = draft.logo;
      if (logo != null) {
        try {
          final path = await SponsoredMomentsService.instance.uploadLogo(
            logo.bytes,
            logo.ext,
          );
          order = PinkaSponsorOrder(
            brand: order.brand,
            tagline: order.tagline,
            linkUrl: order.linkUrl,
            logoPath: path,
            termsAccepted: order.termsAccepted,
            buyer: order.buyer,
          );
        } catch (e) {
          log('SponsorCheckout: logo upload failed — $e');
          if (mounted) {
            setState(() {
              _submitting = false;
              _formError = l.sponsorLogoUploadFailed;
            });
          }
          return;
        }
      }
      final intent = await client.contributeSponsor(
        campaignId: _campaign.campaignId,
        slotKeys: [offer.slotKey],
        order: order,
      );
      log('SponsorCheckout: intent ${intent.contributionId}');
      if (!mounted) return;
      setState(() {
        _intent = intent;
        _orderId = intent.contributionId;
        _phase = _Phase.pay;
        _submitting = false;
      });
      // Narudžba u adresnu traku: reload, Back pa Forward ili kopirana adresa
      // vode na stanje narudžbe umjesto na praznu kartu.
      replaceTimestamp(
        '/v/${widget.youtubeId}/sponzoriraj',
        null,
        query: 'narudzba=${intent.contributionId}',
      );
      _startPolling();
      _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    } on PinkaSlotTaken catch (e) {
      log('SponsorCheckout: slot taken ${e.slotKey}');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _selected = null;
        _phase = _Phase.map;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.sponsorSlotTaken)));
      _loadOffers();
    } on PinkaLoginRequired {
      // Backend ne vidi pravi račun (anonimna sesija, istekao token).
      log('SponsorCheckout: login_required');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = l.sponsorSignInRequired;
      });
      // Prijavljenom korisniku sheet ne bi ponudio ništa novo.
      if (!AuthService.instance.isSignedIn) await _signIn();
    } on PinkaSponsorRejected catch (e) {
      log('SponsorCheckout: rejected $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = switch (e.code) {
          'too_many_holds' => l.sponsorTooManyHolds,
          'invalid_sponsor' when e.detail != null =>
            l.sponsorCheckoutFieldRejected(_fieldLabel(e.detail!, l)),
          _ => l.sponsorCheckoutFailed,
        };
      });
    } catch (e) {
      log('SponsorCheckout: failed — $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = l.sponsorCheckoutFailed;
      });
    }
  }

  /// Sponzorski checkout (i upload loga) traži pravi račun — gost i
  /// anonimna sesija dobivaju `login_required`. Vraća je li korisnik nakon
  /// sheeta prijavljen.
  Future<bool> _signIn() async {
    final l = AppLocalizations.of(context);
    await showAuthSheet(
      context,
      headlineOverride: l.sponsorSignInHeadline,
      subtitleOverride: l.sponsorSignInSubtitle,
    );
    return AuthService.instance.isSignedIn;
  }

  /// Odabir trenutka vodi na formu tek s pravim računom: prijava PRIJE
  /// forme, jer web OAuth je full-page redirect i upisana forma ga ne bi
  /// preživjela.
  Future<void> _pick(SponsorOffer offer) async {
    setState(() {
      _selected = offer;
      _formError = null;
    });
    if (!AuthService.instance.isSignedIn && !await _signIn()) return;
    if (!mounted || _selected?.slotKey != offer.slotKey) return;
    setState(() => _phase = _Phase.form);
  }

  /// `invalid_sponsor:<polje>` → naziv polja kako ga korisnik vidi u formi.
  String _fieldLabel(String field, AppLocalizations l) => switch (field) {
    'brand' => l.sponsorFieldBrand,
    'tagline' => l.sponsorFieldTagline,
    'link_url' => l.sponsorFieldLink,
    'logo_path' => l.sponsorFieldLogo,
    'terms' => l.sponsorTermsAccept,
    'buyer_company' => l.sponsorFieldCompany,
    'buyer_oib' => l.sponsorFieldOib,
    'buyer_vat_id' => l.sponsorFieldVat,
    'buyer_email' => l.sponsorFieldEmail,
    'buyer_reference' => l.sponsorFieldReference,
    final f when f.startsWith('buyer_address') => l.sponsorFieldStreet,
    final f => f,
  };

  /// Stanje narudžbe svakih 5 s. Nema vremenskog limita dok je `pending`,
  /// jer SEPA s novog IBAN-a zna čekati satima (isto pravilo kao SEPA tok zida
  /// podrške). Nakon `paid` se još čeka broj računa (izdaje se asinkrono,
  /// najviše ~10 min); tri uzastopna prazna odgovora bez ikakvog stanja znače
  /// da narudžba ne postoji.
  void _startPolling() {
    _pollTimer?.cancel();
    _missingTicks = 0;
    _invoiceTicks = 0;
    Future<void> tick() async {
      final id = _orderId;
      if (id == null) return;
      final s = await SponsoredMomentsService.instance.orderStatus(id);
      if (!mounted) return;
      setState(() {
        if (s == null) {
          if (_status == null && ++_missingTicks >= 3) {
            _statusMissing = true;
            _pollTimer?.cancel();
          }
          return;
        }
        _missingTicks = 0;
        _status = s;
        _statusMissing = false;
        if (!s.state.isFinal) return;
        _phase = _Phase.status;
        _clockTimer?.cancel();
        final invoiceSettled =
            s.invoiceNumber != null ||
            const {'failed', 'skipped'}.contains(s.invoiceState);
        if (s.state != SponsorOrderState.paid ||
            invoiceSettled ||
            ++_invoiceTicks > 120) {
          _pollTimer?.cancel();
        }
      });
    }

    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => tick());
    tick();
  }

  /// Back iz plaćanja briše QR i opis plaćanja s ekrana (hold ostaje), pa
  /// pita. Narudžba je već u adresnoj traci.
  Future<void> _leave() async {
    if (_phase == _Phase.form) {
      setState(() => _phase = _Phase.map);
      return;
    }
    if (_phase == _Phase.pay) {
      final l = AppLocalizations.of(context);
      final navigator = Navigator.of(context);
      late final VoidCallback unsubscribe;
      unsubscribe = closeOnRouteChange(context, () {
        if (navigator.canPop()) navigator.pop();
      });
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.sponsorLeavePayTitle),
          content: Text(l.sponsorLeavePayBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.sponsorLeavePayConfirm),
            ),
          ],
        ),
      ).whenComplete(unsubscribe);
      if (ok != true || !mounted) return;
    }
    back(context, fallback: '/c/${_campaign.channelSlug}/oglasi');
  }

  String get _orderUrl =>
      'https://domovina.ai/v/${widget.youtubeId}/sponzoriraj?narudzba=$_orderId';

  // ── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      // Sistemski Back (Android, gesta) ide kroz istu provjeru kao strelica.
      canPop: _phase == _Phase.map || _phase == _Phase.status,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _leave),
          title: Text(l.sponsorMapTitle),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                _EpisodeHeader(video: _video, youtubeId: widget.youtubeId),
                const SizedBox(height: 16),
                ...switch (_phase) {
                  _Phase.map => _buildMap(context),
                  _Phase.form => [
                    SponsorCheckoutForm(
                      offer: _selected!,
                      data: _formData,
                      submitting: _submitting,
                      error: _formError,
                      onChangeMoment: () => setState(() {
                        _phase = _Phase.map;
                        _formError = null;
                      }),
                      onSubmit: _submit,
                    ),
                  ],
                  _Phase.pay => _buildPay(context),
                  _Phase.status => _buildStatus(context),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMap(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final offers = _offers;
    if (_loadFailed) {
      return [
        Text(l.sponsorStoreLoadFailed),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: _loadOffers,
            child: Text(l.commonRetry),
          ),
        ),
      ];
    }
    if (offers == null) {
      return const [Center(child: CircularProgressIndicator())];
    }
    if (offers.isEmpty) return [Text(l.sponsorStoreEmpty)];
    return [
      Text(
        l.sponsorMapIntro,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 14),
      SponsorTimelineBar(
        offers: offers,
        durationSeconds: _video?.durationSeconds,
        selectedSlotKey: _selected?.slotKey,
        onTap: (o) => setState(() => _selected = o),
      ),
      const SizedBox(height: 4),
      Text(
        l.sponsorLegend,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 14),
      for (final o in offers)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _OfferCard(
            offer: o,
            selected: o.slotKey == _selected?.slotKey,
            onListen: () =>
                drillDown(context, '/v/${widget.youtubeId}/t/${o.start}'),
            onPick: o.state.isBuyable ? () => _pick(o) : null,
          ),
        ),
    ];
  }

  List<Widget> _buildPay(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final intent = _intent!;
    final hold = intent.holdExpiresAt;
    final holdExpired = hold != null && hold.isBefore(DateTime.now());
    return [
      Text(
        l.sponsorPayTitle,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 12),
      PinkaSepaQr(
        intent: intent,
        memoNote: _Note(
          icon: Icons.warning_amber_rounded,
          text: l.sponsorMemoVerbatim,
          emphasis: true,
        ),
      ),
      const SizedBox(height: 12),
      if (hold != null)
        _Note(
          icon: holdExpired ? Icons.info_outline : Icons.lock_clock,
          text: holdExpired
              ? l.sponsorHoldExpired
              : l.sponsorHoldUntil(
                  '${formatSponsorDate(hold)} ${formatSponsorTime(hold)}',
                ),
        ),
      _Note(icon: Icons.hourglass_top, text: l.sponsorWaitingPayment),
      const SizedBox(height: 12),
      Text(l.sponsorOrderLinkHint, style: theme.textTheme.bodySmall),
      PinkaCopyRow(
        label: l.sponsorCheckoutTitle,
        value: _orderUrl,
        multiline: true,
      ),
    ];
  }

  List<Widget> _buildStatus(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = _status;
    if (s == null) {
      return [
        if (_statusMissing)
          Text(l.sponsorOrderNotFound)
        else
          const Center(child: CircularProgressIndicator()),
      ];
    }
    final heading = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final slot = s.slots.isEmpty ? null : s.slots.first;
    final String title;
    final String? body;
    final now = DateTime.now();
    if (s.isLiveAt(now)) {
      title = l.sponsorPaidTitle;
      body = slot?.liveUntil == null
          ? null
          : l.sponsorPaidUntil(formatSponsorDate(slot!.liveUntil!));
    } else if (s.isAssigned) {
      // Plaćeno i odigrano: zakup je istekao, `state` ostaje `paid`.
      title = l.sponsorPayTitle;
      body = slot?.liveUntil == null
          ? null
          : l.sponsorLeaseEnded(formatSponsorDate(slot!.liveUntil!));
    } else if (s.underpaid) {
      title = l.sponsorOrderFailed;
      body = l.sponsorUnderpaid;
    } else if (s.slotUnassigned) {
      // Novac je stigao, trenutak nije — naslov ne smije reći ni „uživo" ni
      // „nije uspjelo".
      title = l.sponsorPayTitle;
      body = l.sponsorSlotUnassigned;
    } else if (s.hidden) {
      title = l.sponsorOrderFailed;
      body = l.sponsorHidden;
    } else {
      (title, body) = switch (s.state) {
        SponsorOrderState.pending => (
          l.sponsorPayTitle,
          l.sponsorWaitingPayment,
        ),
        SponsorOrderState.expired => (l.sponsorOrderExpired, null),
        _ => (l.sponsorOrderFailed, null),
      };
    }
    return [
      Text(title, style: heading),
      if (body != null) ...[const SizedBox(height: 6), Text(body)],
      if (slot != null) ...[
        const SizedBox(height: 10),
        Text(
          '${formatSponsorClock(slot.start)}–${formatSponsorClock(slot.end)}',
          style: theme.textTheme.bodySmall,
        ),
      ],
      if (s.state == SponsorOrderState.paid) ...[
        const SizedBox(height: 12),
        _Note(
          icon: Icons.receipt_long_outlined,
          text: s.invoiceNumber != null
              ? l.sponsorInvoiceSent(s.invoiceNumber!)
              : l.sponsorInvoicePending,
        ),
        // Ugovor v1 nema mjerenje — brojke stižu s tablicom događaja.
        _Note(icon: Icons.bar_chart, text: l.sponsorStatsPending),
      ],
      if (s.isLiveAt(now) && slot != null) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.play_arrow),
            label: Text(l.sponsorViewOnEpisode),
            onPressed: () =>
                drillDown(context, '/v/${slot.youtubeId}/t/${slot.start}'),
          ),
        ),
      ],
    ];
  }
}

class _EpisodeHeader extends StatelessWidget {
  final ChannelVideo? video;
  final String youtubeId;

  const _EpisodeHeader({required this.video, required this.youtubeId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final v = video;
    if (v == null) return const SizedBox.shrink();
    final topics = SponsorTopic.classify(
      topics: v.topics,
      title: v.displayTitle,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          v.displayTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (v.topics.isNotEmpty || topics.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            l.sponsorMapTopics,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final t in topics)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(sponsorTopicLabel(t, l)),
                ),
              for (final t in v.topics)
                Chip(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  label: Text(t),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  final SponsorOffer offer;
  final bool selected;
  final VoidCallback onListen;
  final VoidCallback? onPick;

  const _OfferCard({
    required this.offer,
    required this.selected,
    required this.onListen,
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final o = offer;
    final accent = AppTheme.sponsoredAccent(theme.brightness);
    final muted = theme.colorScheme.onSurfaceVariant;
    final zone = sponsorZoneLabel(o.zone, l);
    final buyable = o.state.isBuyable;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? theme.colorScheme.onSurface
              : (buyable ? accent : theme.colorScheme.outlineVariant),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${formatSponsorClock(o.start)}–${formatSponsorClock(o.end)}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (zone.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(zone, style: theme.textTheme.labelMedium),
              ],
              const Spacer(),
              Text(
                sponsorStateLabel(o, l),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: buyable ? accent : muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (o.title != null) ...[
            const SizedBox(height: 4),
            Text(o.title!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 4),
          Text(
            '${l.sponsorPriceGross(fmtEur(o.priceCents))} · '
            '${l.sponsorRunDays(o.runDays)}',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(l.sponsoredListen),
                onPressed: onListen,
              ),
              if (onPick != null)
                FilledButton(onPressed: onPick, child: Text(l.sponsorPick)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool emphasis;

  const _Note({required this.icon, required this.text, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = emphasis
        ? AppTheme.sponsoredAccent(theme.brightness)
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: emphasis ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
