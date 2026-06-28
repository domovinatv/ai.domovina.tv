/// RevenueCat purchase rail — platform-switched facade.
///
/// Mobile (iOS/Android/macOS) loads the real `purchases_flutter`-backed
/// implementation. Web — and any target without `dart:io` — loads a no-op stub
/// so the `--wasm` build never pulls `purchases_flutter` (which imports
/// `dart:html`-shaped code) into the web compilation. This mirrors the
/// conditional-import pattern used by `local_prefs.dart` and the passkey
/// platform packages (see CLAUDE.md + wasm gotchas).
///
/// IMPORTANT: gate the conditional on `dart.library.io` (native VM/AOT), NOT
/// `dart.library.html` — under `--wasm` the html library check resolves wrong
/// and would compile the SDK on web.
///
/// `RevenueCatService.instance` exposes the same API on both: `configure`,
/// `logIn`/`logOut`, `getOfferings`, `purchase`, `restore`, plus an
/// `optimisticPlus` notifier for mobile instant-unlock. On web every method is
/// a safe no-op and `isSupported` is false — web sells via the RC Web Billing
/// hosted checkout (see PaywallScreen) and reads entitlement state from
/// Supabase like every other platform.
library;

export 'revenue_cat/rc_models.dart';
export 'revenue_cat/revenue_cat_service_stub.dart'
    if (dart.library.io) 'revenue_cat/revenue_cat_service_native.dart';
