import 'package:flutter/foundation.dart' show kIsWeb;
import 'page_meta_web.dart' if (dart.library.io) 'page_meta_native.dart'
    as platform;

/// Runtime update `document.title` + og/twitter meta tagova po ruti.
///
/// Crawleri dobivaju prave tagove edge-side u web/_worker.js (oni ne
/// izvršavaju JS) — ovo je za KORISNIKE u živoj SPA sesiji: naslov taba,
/// history/bookmark naslovi i share-sheet preview koji čita živi DOM
/// (npr. iOS Safari "Dijeli"). Format naslova zrcali worker injectore
/// (`<specifično> – DOMOVINA.ai`).
///
/// Wasm-safe: web implementacija koristi package:web + dart:js_interop
/// (NIKAD dart:html — ruši --wasm build). Na nativu je no-op.
void setPageMeta({required String title, String? description}) {
  if (!kIsWeb) return;
  platform.setPageMetaImpl(title: title, description: description);
}

/// Vrati default (index.html) naslov i opis — za home/neutralne rute.
void resetPageMeta() {
  if (!kIsWeb) return;
  platform.resetPageMetaImpl();
}
