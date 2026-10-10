/// Conditional-import wrapper za korisnikove signale o mreži (web).
/// Web build čita `navigator.connection`, native stub. Ista indirekcija kao
/// `mobile_web_detect.dart`.
library;

import 'network_hints_web.dart'
    if (dart.library.io) 'network_hints_stub.dart' as platform;

/// True kad je korisnik uključio uštedu podataka ili je veza 2G / slow-2g.
/// Tada se ne dohvaća ništa što nije izravno zatražio (predučitavanje).
/// Preglednik bez Network Information API-ja (Safari, Firefox) → false.
bool prefersReducedData() => platform.prefersReducedData();
