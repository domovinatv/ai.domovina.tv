import 'package:flutter/foundation.dart' show kIsWeb;
import 'url_sync_web.dart' if (dart.library.io) 'url_sync_native.dart'
    as platform;

/// Update browser address bar na `<basePath>/t/<seconds>` (ili `basePath` ako
/// je seconds 0/null), bez triggera router refresha.
///
/// Razlog: dok player ide, želimo da copy-paste URL iz adresne trake uvijek
/// reflektira trenutnu poziciju, a ne onu s koje je epizoda otvorena.
///
/// [langSuffix]: '/en' da se EN jezik perzistira u URL-u kroz playback;
/// null/empty za HR (default).
///
/// Na nativu je no-op (nema adresne trake).
void replaceTimestamp(String basePath, int? seconds, {String? langSuffix}) {
  if (!kIsWeb) return;
  platform.replaceTimestampImpl(basePath, seconds, langSuffix: langSuffix);
}

/// Update samo jezik u adresnoj traci (bez timestamp segmenta). Koristi se
/// kad je epizoda otvorena na bazi URL-a (player jos nije pokrenuo
/// timestamp sync) a korisnik klikne EN/HR toggle.
void replaceLanguage(String basePath, {required bool isEn, int? seconds}) {
  if (!kIsWeb) return;
  platform.replaceTimestampImpl(basePath, seconds,
      langSuffix: isEn ? '/en' : null);
}
