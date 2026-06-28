/// Web / unsupported-platform stub for [RevenueCatService].
///
/// Selected by the conditional export in `revenue_cat_service.dart` whenever
/// `dart:io` is absent (web, including `--wasm`). Every method is a no-op so the
/// app compiles and runs with the SDK fully bypassed. Web purchases go through
/// the RevenueCat Web Billing hosted checkout; entitlement state is read from
/// Supabase (see EntitlementService).
library;

import 'package:flutter/foundation.dart';
import '../../main.dart' show log;
import 'rc_models.dart';

class RevenueCatService {
  static final RevenueCatService instance = RevenueCatService._();
  RevenueCatService._();

  /// Web has no native purchase SDK.
  bool get isSupported => false;

  /// Optimistic unlock from the SDK — always false on web (no SDK).
  final ValueNotifier<bool> optimisticPlus = ValueNotifier<bool>(false);

  Future<void> configure() async {
    log('RevenueCatService(stub): web/unsupported — SDK bypassed');
  }

  Future<void> logIn(String appUserId) async {}

  Future<void> logOut() async {}

  Future<RcOfferings> getOfferings() async => RcOfferings.empty;

  Future<RcPurchaseResult> purchase(RcPackage package) async =>
      RcPurchaseResult.unsupported;

  Future<RcPurchaseResult> restore() async => RcPurchaseResult.unsupported;
}
