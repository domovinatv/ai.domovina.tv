import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show log;
import 'local_prefs.dart';
import 'mobile_web_detect.dart';
import 'open_url.dart';

/// App Store / Google Play poveznice na native aplikaciju.
const String iosAppStoreUrl =
    'https://apps.apple.com/us/app/domovina-ai/id6781716801';
const String androidPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=ai.domovina';

/// localStorage flag — pamti da je banner već pokazan pa ne gnjavimo korisnika
/// pri svakom učitavanju.
const String _dismissKey = 'app_install_banner_seen';

/// Jednokratni snackbar koji nudi preuzimanje native aplikacije kad je web
/// otvoren u mobilnom browseru i NIJE već instaliran kao PWA.
///
/// Hibrid s Apple Smart App Bannerom (`apple-itunes-app` meta u index.html):
/// - iOS Safari → NE prikazuje snackbar (Apple nativni banner pokriva to);
/// - iOS Chrome/Firefox/Edge → snackbar (tamo Smart App Banner ne postoji);
/// - Android → snackbar (nema meta-tag ekvivalenta).
///
/// No-op na desktopu, u native buildu, u PWA standalone modu, i nakon što je
/// jednom prikazan (persistira se u localStorage).
void maybeShowAppInstallBanner(BuildContext context) {
  if (!kIsWeb) return;

  final os = mobileWebOs();
  if (os != 'ios' && os != 'android') return; // samo mobilni browseri
  if (os == 'ios' && isIosSafari()) return; // Smart App Banner već pokriva
  if (isStandalonePwa()) return; // već instaliran kao PWA → ne nudi store
  if (getLocalStorageString(_dismissKey) == '1') return; // već viđeno

  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final url = os == 'ios' ? iosAppStoreUrl : androidPlayStoreUrl;

  log('app-install banner: prikazujem za $os');

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        os == 'ios' ? l.appInstallBannerIos : l.appInstallBannerAndroid,
      ),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: l.appInstallBannerAction,
        onPressed: () => openUrl(url),
      ),
    ),
  );

  // Zabilježi da je pokazan — jednokratno, čak i ako ga korisnik odbaci
  // swipeom bez tapkanja na akciju.
  setLocalStorageString(_dismissKey, '1');
}
