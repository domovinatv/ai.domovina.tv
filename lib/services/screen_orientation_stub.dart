/// Native implementacija brave orijentacije (`SystemChrome`).
///
/// Ime „stub" je zbog konvencije uvjetnog importa u repou
/// (`local_prefs_stub.dart`, `browser_fullscreen_stub.dart`) — ovdje to NIJE
/// prazna implementacija: mobilni native je jedina platforma koja pravi
/// landscape dobiva bez ikakvog kompromisa.
///
/// Ovo je **prva upotreba `SystemChrome` u repou**. Zato je uska: pali se samo
/// iz rotacijskog fullscreena i vraća stanje na izlazu.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

/// `setPreferredOrientations` je no-op izvan iOS-a/Androida — desktop native
/// (macOS/Windows/Linux) neka ide istom putanjom kao i dosad, bez diranja
/// sistemskog stanja.
bool get canLockOrientation =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

Future<bool> lockLandscape() async {
  if (!canLockOrientation) return false;
  // iOS poštuje app-forsiranu orijentaciju unatoč sistemskoj bravi rotacije —
  // to je odluka D3 (korisnik s uključenom bravom svejedno dobije landscape).
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: const [],
  );
  return true;
}

Future<void> unlockOrientation() async {
  if (!canLockOrientation) return;
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}
