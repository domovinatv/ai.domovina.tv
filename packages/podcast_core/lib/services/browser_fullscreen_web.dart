import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get isBrowserFullscreen {
  try {
    return web.document.fullscreenElement != null;
  } catch (_) {
    return false;
  }
}

void Function() addFullscreenChangeListener(void Function() callback) {
  final listener = ((web.Event _) {
    callback();
  }).toJS;
  web.document.addEventListener('fullscreenchange', listener);
  // Safari < 16.4 koristi webkit prefix.
  web.document.addEventListener('webkitfullscreenchange', listener);
  return () {
    web.document.removeEventListener('fullscreenchange', listener);
    web.document.removeEventListener('webkitfullscreenchange', listener);
  };
}
