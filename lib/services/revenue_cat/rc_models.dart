/// Platform-neutral RevenueCat value types.
///
/// These contain NO `purchases_flutter` imports so they are safe to compile on
/// every target — including the web/`--wasm` build where the SDK is fully
/// bypassed. The native implementation maps the SDK's `Package`/`CustomerInfo`
/// into these; the paywall and the rest of the app only ever see these types.
library;

/// The single entitlement the whole app gates on. Must match the RevenueCat
/// entitlement `lookup_key` and the value the webhook writes into
/// `domovina_ai.subscriptions.entitlement`. Never gate on a product id.
const String kDomovinaPlusEntitlement = 'domovina_plus';

/// The RevenueCat offering we render packages from.
const String kDefaultOfferingId = 'default';

/// Subscription cadence as shown on the paywall.
enum RcPlan { monthly, annual, lifetime, other }

/// A purchasable package, flattened from a RevenueCat `Package`.
class RcPackage {
  /// RevenueCat package identifier (`$rc_monthly`, `$rc_annual`, `$rc_lifetime`).
  final String id;
  final RcPlan plan;

  /// Underlying store product id (e.g. `domovina_plus_annual`).
  final String productId;

  /// Localized, currency-formatted price (e.g. `4,99 €`).
  final String priceString;
  final String title;
  final String? description;

  /// Web Billing hosted-checkout URL for this package, when RevenueCat provides
  /// one. Used on web (the SDK can't run there) to redirect to checkout.
  final String? webCheckoutUrl;

  const RcPackage({
    required this.id,
    required this.plan,
    required this.productId,
    required this.priceString,
    required this.title,
    this.description,
    this.webCheckoutUrl,
  });
}

/// The packages available from the `default` offering, plan-ordered.
class RcOfferings {
  final List<RcPackage> packages;
  const RcOfferings(this.packages);

  static const RcOfferings empty = RcOfferings(<RcPackage>[]);

  bool get isEmpty => packages.isEmpty;

  RcPackage? _firstOfPlan(RcPlan p) {
    for (final pkg in packages) {
      if (pkg.plan == p) return pkg;
    }
    return null;
  }

  RcPackage? get monthly => _firstOfPlan(RcPlan.monthly);
  RcPackage? get annual => _firstOfPlan(RcPlan.annual);
  RcPackage? get lifetime => _firstOfPlan(RcPlan.lifetime);
}

/// Outcome of a purchase/restore attempt.
enum RcPurchaseStatus { success, cancelled, error, unsupported }

class RcPurchaseResult {
  final RcPurchaseStatus status;

  /// Whether `domovina_plus` is active in the resulting `CustomerInfo`
  /// (optimistic unlock signal; Supabase remains authoritative).
  final bool isPlusActive;

  /// Human-readable Croatian message for the error case.
  final String? message;

  const RcPurchaseResult(this.status, {this.isPlusActive = false, this.message});

  static const RcPurchaseResult cancelled =
      RcPurchaseResult(RcPurchaseStatus.cancelled);
  static const RcPurchaseResult unsupported =
      RcPurchaseResult(RcPurchaseStatus.unsupported);

  bool get ok => status == RcPurchaseStatus.success;
}
