import 'dart:js_interop';
import 'package:web/web.dart' as web;

void listenForAppUpdateImpl(void Function() onUpdateAvailable) {
  web.window.addEventListener(
    'flutter-app-updated',
    (web.Event e) { onUpdateAvailable(); }.toJS,
  );
}

void reloadPageImpl() {
  web.window.location.reload();
}

void hardReloadImpl() async {
  try {
    // Clear all caches (Cache API)
    final cacheNames = await web.window.caches.keys().toDart;
    for (final name in cacheNames.toDart) {
      await web.window.caches.delete(name.toDart).toDart;
    }
    // Unregister all Service Workers
    final regs = await web.window.navigator.serviceWorker
        .getRegistrations()
        .toDart;
    for (final reg in regs.toDart) {
      await reg.unregister().toDart;
    }
  } catch (_) {}
  // Navigate with cache-buster to bypass bfcache
  final base = web.window.location.origin;
  final bust = DateTime.now().millisecondsSinceEpoch;
  web.window.location.replace('$base/?_cb=$bust');
}
