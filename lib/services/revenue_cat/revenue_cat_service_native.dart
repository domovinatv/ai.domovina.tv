/// Native (iOS / Android / macOS) RevenueCat implementation.
///
/// Selected by the conditional export in `revenue_cat_service.dart` when
/// `dart:io` is available. Wraps `purchases_flutter` and exposes the same API
/// as the web stub. Android TV (Leanback) is treated as unsupported — it never
/// sells subscriptions; TV reads entitlement state from Supabase like the web.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../main.dart' show log;
import '../tv_mode.dart';
import 'rc_models.dart';

/// Publishable SDK keys — public by design, injected at build via --dart-define
/// (see scripts/build-mobile-release.sh). For TestStore QA put the `test_…` key
/// in both. macOS shares the App Store (iOS) key.
const String _iosKey = String.fromEnvironment('RC_PUBLIC_SDK_KEY_IOS');
const String _androidKey = String.fromEnvironment('RC_PUBLIC_SDK_KEY_ANDROID');

class RevenueCatService {
  static final RevenueCatService instance = RevenueCatService._();
  RevenueCatService._();

  bool _configured = false;
  String? _currentAppUserId;

  final ValueNotifier<bool> optimisticPlus = ValueNotifier<bool>(false);

  /// True only on real purchase-capable platforms with a key configured.
  /// Android TV is excluded (no in-app purchase surface there).
  bool get isSupported {
    if (TvMode.isTv) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => _iosKey.isNotEmpty,
      TargetPlatform.android => _androidKey.isNotEmpty,
      _ => false,
    };
  }

  String get _platformKey => switch (defaultTargetPlatform) {
        TargetPlatform.iOS || TargetPlatform.macOS => _iosKey,
        TargetPlatform.android => _androidKey,
        _ => '',
      };

  /// Configure the SDK once. No-op (and no SDK call) when unsupported or the
  /// platform key is missing — so a keyless dev/CI build still runs.
  Future<void> configure() async {
    if (_configured) return;
    if (!isSupported) {
      log('RevenueCatService: unsupported platform/TV or missing key — bypassed');
      return;
    }
    try {
      await Purchases.setLogLevel(kReleaseMode ? LogLevel.warn : LogLevel.info);
      await Purchases.configure(PurchasesConfiguration(_platformKey));
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      _configured = true;
      log('RevenueCatService: configured ($defaultTargetPlatform)');
    } catch (e) {
      log('RevenueCatService.configure failed: $e');
    }
  }

  void _onCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active.containsKey(kDomovinaPlusEntitlement);
    optimisticPlus.value = active;
    log('RevenueCatService: CustomerInfo update — plus=$active');
  }

  /// Alias the RevenueCat customer to the Supabase auth UUID. Idempotent —
  /// re-calling with the same id is a cheap no-op. Only call for permanent
  /// (non-anonymous) users; anonymous users keep RC's own anonymous id so a
  /// later purchase attaches to a durable identity after account-link.
  Future<void> logIn(String appUserId) async {
    if (!_configured || appUserId.isEmpty) return;
    if (_currentAppUserId == appUserId) return;
    try {
      final result = await Purchases.logIn(appUserId);
      _currentAppUserId = appUserId;
      _onCustomerInfo(result.customerInfo);
      log('RevenueCatService: logIn $appUserId');
    } catch (e) {
      log('RevenueCatService.logIn failed: $e');
    }
  }

  Future<void> logOut() async {
    if (!_configured || _currentAppUserId == null) return;
    try {
      final info = await Purchases.logOut();
      _currentAppUserId = null;
      _onCustomerInfo(info);
      log('RevenueCatService: logOut');
    } catch (e) {
      // logOut throws if already anonymous — benign.
      log('RevenueCatService.logOut: $e');
      _currentAppUserId = null;
    }
  }

  Future<RcOfferings> getOfferings() async {
    if (!_configured) return RcOfferings.empty;
    try {
      final offerings = await Purchases.getOfferings();
      final offering =
          offerings.getOffering(kDefaultOfferingId) ?? offerings.current;
      if (offering == null) return RcOfferings.empty;
      final packages = offering.availablePackages.map(_mapPackage).toList();
      return RcOfferings(packages);
    } catch (e) {
      log('RevenueCatService.getOfferings failed: $e');
      return RcOfferings.empty;
    }
  }

  Future<RcPurchaseResult> purchase(RcPackage package) async {
    if (!_configured) return RcPurchaseResult.unsupported;
    final native = await _nativePackage(package.id);
    if (native == null) {
      return const RcPurchaseResult(RcPurchaseStatus.error,
          message: 'Paket više nije dostupan. Pokušaj ponovo.');
    }
    try {
      final result = await Purchases.purchase(PurchaseParams.package(native));
      final active = result.customerInfo.entitlements.active
          .containsKey(kDomovinaPlusEntitlement);
      optimisticPlus.value = active;
      return RcPurchaseResult(
        active ? RcPurchaseStatus.success : RcPurchaseStatus.error,
        isPlusActive: active,
        message: active ? null : 'Kupnja nije aktivirala pretplatu.',
      );
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return RcPurchaseResult.cancelled;
      }
      log('RevenueCatService.purchase error: ${code.name} ${e.message}');
      return RcPurchaseResult(RcPurchaseStatus.error,
          message: _friendly(code));
    } catch (e) {
      log('RevenueCatService.purchase unexpected: $e');
      return const RcPurchaseResult(RcPurchaseStatus.error,
          message: 'Kupnja nije uspjela. Pokušaj ponovo.');
    }
  }

  Future<RcPurchaseResult> restore() async {
    if (!_configured) return RcPurchaseResult.unsupported;
    try {
      final info = await Purchases.restorePurchases();
      final active =
          info.entitlements.active.containsKey(kDomovinaPlusEntitlement);
      optimisticPlus.value = active;
      return RcPurchaseResult(
        active ? RcPurchaseStatus.success : RcPurchaseStatus.error,
        isPlusActive: active,
        message: active ? null : 'Nismo pronašli aktivnu pretplatu za vraćanje.',
      );
    } catch (e) {
      log('RevenueCatService.restore failed: $e');
      return const RcPurchaseResult(RcPurchaseStatus.error,
          message: 'Vraćanje kupnji nije uspjelo. Pokušaj ponovo.');
    }
  }

  Future<Package?> _nativePackage(String id) async {
    try {
      final offerings = await Purchases.getOfferings();
      final offering =
          offerings.getOffering(kDefaultOfferingId) ?? offerings.current;
      for (final p in offering?.availablePackages ?? const <Package>[]) {
        if (p.identifier == id) return p;
      }
    } catch (e) {
      log('RevenueCatService._nativePackage failed: $e');
    }
    return null;
  }

  RcPackage _mapPackage(Package p) => RcPackage(
        id: p.identifier,
        plan: _planOf(p.packageType),
        productId: p.storeProduct.identifier,
        priceString: p.storeProduct.priceString,
        title: p.storeProduct.title,
        description: p.storeProduct.description,
        webCheckoutUrl: p.webCheckoutUrl,
      );

  RcPlan _planOf(PackageType t) => switch (t) {
        PackageType.monthly => RcPlan.monthly,
        PackageType.annual => RcPlan.annual,
        PackageType.lifetime => RcPlan.lifetime,
        _ => RcPlan.other,
      };

  String _friendly(PurchasesErrorCode code) => switch (code) {
        PurchasesErrorCode.purchaseNotAllowedError =>
          'Kupnja nije dopuštena na ovom uređaju.',
        PurchasesErrorCode.paymentPendingError =>
          'Plaćanje je u obradi — pretplata se aktivira čim bude potvrđeno.',
        PurchasesErrorCode.productAlreadyPurchasedError =>
          'Već imaš ovu pretplatu. Pokušaj "Vrati kupnje".',
        PurchasesErrorCode.networkError =>
          'Nema veze s trgovinom. Provjeri internet pa pokušaj ponovo.',
        PurchasesErrorCode.storeProblemError =>
          'Trgovina trenutno ne odgovara. Pokušaj kasnije.',
        _ => 'Kupnja nije uspjela. Pokušaj ponovo.',
      };
}
