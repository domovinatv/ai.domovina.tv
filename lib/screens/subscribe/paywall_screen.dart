/// DOMOVINA Plus paywall + purchase flow.
///
/// One entitlement (`domovina_plus`), three packages. Behaviour per platform:
///  - Mobile (iOS/Android/macOS, SDK configured): fetch the `default` offering
///    and render real localized prices; purchase via the RevenueCat SDK; show
///    Restore Purchases + a Manage Subscription deep link (store requirement).
///  - Web (no SDK): redirect to the RevenueCat Web Billing hosted checkout,
///    passing the Supabase UUID as the customer id. The webhook→Supabase row
///    drives the unlock on return.
///
/// Entitlement state is read from [EntitlementService]; never gates on a product
/// id. Anonymous users are prompted to link an account before any purchase so
/// the purchase attaches to a durable identity.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart' show log;
import '../../onboarding/ui/auth_sheet.dart';
import '../../services/auth_service.dart';
import '../../services/entitlement_service.dart';
import '../../services/locale_service.dart';
import '../../services/open_url.dart';
import '../../services/revenue_cat_service.dart';
import '../../theme/app_theme.dart';
import 'upgrade_trigger.dart';
import '../../router/nav.dart';

/// RevenueCat Web Billing hosted-checkout base URL (no SDK on web). The Supabase
/// UUID is appended as the customer id: `<base>/<uuid>`. Injected via
/// --dart-define at web build (scripts/deploy.sh). Empty until Web Billing /
/// Stripe is connected in the RC dashboard (human step) — UI degrades to a note.
const String _webCheckoutBase = String.fromEnvironment('RC_WEB_CHECKOUT_URL');

/// Indicative EUR prices shown on web / when the SDK offering is unavailable.
/// PROPOSALS pending owner confirmation; the store/checkout shows the
/// authoritative price. See docs/payments/pricing-and-tiers.md.
class _IndicativePlan {
  final RcPlan plan;
  final String name;
  final String price;
  final String cadence;
  final String? note;
  const _IndicativePlan(this.plan, this.name, this.price, this.cadence,
      [this.note]);
}

List<_IndicativePlan> _indicativePlans(AppLocalizations l) => [
  _IndicativePlan(RcPlan.annual, l.channelPlanAnnual, '39,99 €',
      l.channelPlanPerYear, l.channelPlanSaveBadge),
  _IndicativePlan(RcPlan.monthly, l.channelPlanMonthly, '4,99 €',
      l.channelPlanPerMonth),
  _IndicativePlan(RcPlan.lifetime, l.channelPlanLifetime, '99,99 €',
      l.channelPlanOneTime, l.channelPlanFounderBadge),
];

/// What Plus actually unlocks TODAY. Every line here is a purchase claim, so it
/// may only list behaviour that exists in the shipped app (search limit 12→30 in
/// `search_overlay.dart`, the badge in `plus_badge.dart`, plus the support
/// itself). Planned work belongs in [_roadmap], never here.
List<(IconData, String)> _plusBenefits(AppLocalizations l) => [
  (Icons.search, l.channelBenefitSearch),
  (Icons.favorite, l.channelBenefitBadge),
  (Icons.volunteer_activism, l.channelBenefitSupport),
];

/// Directions we're exploring — explicitly NOT part of the purchase. Rendered
/// below the prices, muted and non-interactive (see [_roadmap]).
///
/// An item may only go here if it does NOT exist yet. Semantic search was
/// listed and removed 2026-07-31: it already ships, free for everyone
/// (`search_overlay.dart` `_runSemantic()`) — Plus only widens the result
/// limit, which is a benefit above, so listing it here contradicted that line.
List<String> _plusRoadmap(AppLocalizations l) => [
  l.plusRoadmapOffline,
  l.plusRoadmapExport,
];

/// Open the contextual paywall for a gated feature. Use from any feature gate:
/// `openPaywall(context, UpgradeTrigger.search)`.
void openPaywall(BuildContext context, [UpgradeTrigger trigger = UpgradeTrigger.generic]) {
  drillDown(context, '/subscribe?from=${trigger.slug}');
}

class PaywallScreen extends StatefulWidget {
  final UpgradeTrigger trigger;
  const PaywallScreen({super.key, this.trigger = UpgradeTrigger.generic});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  RcOfferings? _offerings;
  bool _loading = false;
  bool _purchasing = false;

  bool get _sdkSupported => RevenueCatService.instance.isSupported;

  @override
  void initState() {
    super.initState();
    if (_sdkSupported) _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    setState(() => _loading = true);
    final offerings = await RevenueCatService.instance.getOfferings();
    if (!mounted) return;
    setState(() {
      _offerings = offerings;
      _loading = false;
    });
  }

  // --- account gate -------------------------------------------------------

  bool get _isAnonymous => AuthService.instance.isAnonymous;

  Future<void> _promptLinkAccount() async {
    final l = AppLocalizations.of(context);
    await showAuthSheet(
      context,
      origin: AuthSheetOrigin.account,
      headlineOverride: l.channelSignInToContinue,
      subtitleOverride: l.channelSubscriptionTiedToAccount,
    );
    if (mounted) setState(() {}); // refresh anon state after the sheet closes
  }

  // --- purchase (mobile) --------------------------------------------------

  Future<void> _purchase(RcPackage pkg) async {
    if (_isAnonymous) {
      await _promptLinkAccount();
      if (_isAnonymous) return; // still not linked
    }
    setState(() => _purchasing = true);
    final result = await RevenueCatService.instance.purchase(pkg);
    if (!mounted) return;
    setState(() => _purchasing = false);

    switch (result.status) {
      case RcPurchaseStatus.success:
        unawaited(EntitlementService.instance.refresh());
        _snack(appStrings.channelWelcomeToPlus);
        if (mounted) context.pop();
      case RcPurchaseStatus.cancelled:
        break; // silent — user backed out
      case RcPurchaseStatus.unsupported:
        _snack(appStrings.channelPurchaseUnavailableDevice);
      case RcPurchaseStatus.error:
        _snack(result.message ?? appStrings.channelPurchaseFailed);
    }
  }

  Future<void> _restore() async {
    setState(() => _purchasing = true);
    final result = await RevenueCatService.instance.restore();
    if (!mounted) return;
    setState(() => _purchasing = false);
    if (result.ok) {
      unawaited(EntitlementService.instance.refresh());
      _snack(appStrings.channelSubscriptionRestored);
      if (mounted) context.pop();
    } else {
      _snack(result.message ?? appStrings.channelNoPurchaseToRestore);
    }
  }

  void _openManageSubscription() {
    final url = defaultTargetPlatform == TargetPlatform.android
        ? 'https://play.google.com/store/account/subscriptions'
        : 'https://apps.apple.com/account/subscriptions';
    openUrl(url);
  }

  // --- purchase (web hosted checkout) -------------------------------------

  Future<void> _webCheckout() async {
    if (_isAnonymous) {
      await _promptLinkAccount();
      if (_isAnonymous) return;
    }
    final uid = AuthService.instance.userId;
    if (_webCheckoutBase.isEmpty || uid.isEmpty) {
      _snack(appStrings.channelWebBillingSoon);
      log('Paywall: web checkout base not configured');
      return;
    }
    final base = _webCheckoutBase.endsWith('/')
        ? _webCheckoutBase.substring(0, _webCheckoutBase.length - 1)
        : _webCheckoutBase;
    openUrl('$base/$uid');
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('DOMOVINA Plus')),
      body: ValueListenableBuilder<bool>(
        valueListenable: EntitlementService.instance.isPlus,
        builder: (context, isPlus, _) {
          return Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _hero(cs),
                      const SizedBox(height: 24),
                      if (isPlus)
                        _alreadyPlus(cs)
                      else ...[
                        _benefits(cs),
                        const SizedBox(height: 24),
                        if (_isAnonymous) _linkAccountCard(cs),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          ..._planSection(cs),
                        const SizedBox(height: 16),
                        _legal(cs),
                      ],
                      _roadmap(cs),
                    ],
                  ),
                ),
              ),
              if (_purchasing)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x88000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _hero(ColorScheme cs) {
    final l = AppLocalizations.of(context);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.croBlue,
              borderRadius: BorderRadius.circular(999),
              border: Border.fromBorderSide(
                  AppTheme.brandRim(Theme.of(context).brightness)),
            ),
            child: const Text('PLUS',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2)),
          ),
          const SizedBox(height: 16),
          Text(widget.trigger.headline(l),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
          const SizedBox(height: 8),
          Text(widget.trigger.subtitle(l),
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      );
  }

  Widget _benefits(ColorScheme cs) => Column(
        children: [
          for (final (icon, label) in _plusBenefits(AppLocalizations.of(context)))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: cs.primary),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Text(label,
                          style: Theme.of(context).textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      );

  Widget _linkAccountCard(ColorScheme cs) {
    final l = AppLocalizations.of(context);
    return Card(
        margin: const EdgeInsets.only(bottom: 16),
        color: cs.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.channelSignInFirst,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: cs.primary)),
              const SizedBox(height: 6),
              Text(l.channelSubscriptionTiedToAccount,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _promptLinkAccount,
                child: Text(l.commonSignIn),
              ),
            ],
          ),
        ),
      );
  }

  /// Mobile real packages when available; otherwise indicative tiles (web or
  /// SDK offering missing).
  List<Widget> _planSection(ColorScheme cs) {
    final l = AppLocalizations.of(context);
    final offerings = _offerings;
    final realPackages = offerings == null
        ? const <RcPackage>[]
        : [
            if (offerings.annual != null) offerings.annual!,
            if (offerings.monthly != null) offerings.monthly!,
            if (offerings.lifetime != null) offerings.lifetime!,
          ];

    if (_sdkSupported && realPackages.isNotEmpty) {
      return [
        for (final pkg in realPackages) _realPackageTile(cs, pkg),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _restore,
            child: Text(l.channelRestorePurchases),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: _openManageSubscription,
            child: Text(l.channelManageSubscription),
          ),
        ),
      ];
    }

    // Web / fallback: indicative tiles → hosted checkout.
    return [
      for (final p in _indicativePlans(l)) _indicativeTile(cs, p),
      const SizedBox(height: 12),
      Text(
        kIsWeb ? l.channelCheckoutNote : l.channelPricesIndicative,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: cs.onSurfaceVariant),
        textAlign: TextAlign.center,
      ),
    ];
  }

  Widget _realPackageTile(ColorScheme cs, RcPackage pkg) {
    final highlight = pkg.plan == RcPlan.annual;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: highlight ? AppTheme.croBlue : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _purchasing ? null : () => _purchase(pkg),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: highlight
                  ? Border.fromBorderSide(
                      AppTheme.brandRim(Theme.of(context).brightness))
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pkg.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: highlight ? Colors.white : cs.primary,
                              fontWeight: FontWeight.w700)),
                      if (pkg.description != null &&
                          pkg.description!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(pkg.description!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: highlight
                                    ? Colors.white70
                                    : cs.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                Text(pkg.priceString,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: highlight ? Colors.white : cs.primary,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _indicativeTile(ColorScheme cs, _IndicativePlan p) {
    final highlight = p.plan == RcPlan.annual;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: highlight ? AppTheme.croBlue : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _webCheckout,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: highlight
                  ? Border.fromBorderSide(
                      AppTheme.brandRim(Theme.of(context).brightness))
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(p.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      color: highlight
                                          ? Colors.white
                                          : cs.primary,
                                      fontWeight: FontWeight.w700)),
                          if (p.note != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.croRed,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(p.note!,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(p.price,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: highlight ? Colors.white : cs.primary,
                            fontWeight: FontWeight.w800)),
                    Text(p.cadence,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: highlight
                                ? Colors.white70
                                : cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _alreadyPlus(ColorScheme cs) {
    final l = AppLocalizations.of(context);
    return Card(
        color: cs.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.verified, size: 48, color: cs.primary),
              const SizedBox(height: 12),
              Text(l.channelAlreadyPlus,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: cs.primary)),
              const SizedBox(height: 6),
              Text(l.channelThanksSupportingArchive,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              if (_sdkSupported)
                OutlinedButton(
                  onPressed: _openManageSubscription,
                  child: Text(l.channelManageSubscription),
                ),
            ],
          ),
        ),
      );
  }

  /// „U planu" — roadmap, not an offer. Sits BELOW the prices (and below the
  /// already-Plus card), visually detached, muted, with plain dot markers and
  /// zero interactive elements: an App Store reviewer must read it as a note
  /// about the future, not as a shipped-but-broken feature (guideline 2.1).
  Widget _roadmap(ColorScheme cs) {
    final l = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(l.plusRoadmapTitle,
              style: textTheme.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final item in _plusRoadmap(l))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Icon(Icons.circle_outlined,
                        size: 10, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item,
                        style: textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(l.plusRoadmapDisclaimer,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _legal(ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          AppLocalizations.of(context).channelLegalAutoRenew,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      );
}

/// Explicit fire-and-forget.
void unawaited(Future<void> _) {}
