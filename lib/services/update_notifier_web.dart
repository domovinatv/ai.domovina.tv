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
    final regs = await web.window.navigator.serviceWorker
        .getRegistrations()
        .toDart;
    for (final reg in regs.toDart) {
      await reg.unregister().toDart;
    }
  } catch (_) {}
  web.window.location.reload();
}
