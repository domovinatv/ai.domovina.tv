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
