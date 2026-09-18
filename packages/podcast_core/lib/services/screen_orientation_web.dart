/// Web implementacija brave orijentacije (Screen Orientation API).
///
/// Ucitava se preko `screen_orientation.dart` kad je `dart.library.js_interop`
/// dostupan (dart2js **i** dart2wasm).
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// `screen.orientation` postoji na svim modernim browserima, ali `lock` NE:
/// WebKit (iPhone Safari, iOS Chrome) ga jednostavno ne implementira.
bool get canLockOrientation {
  try {
    return web.window.screen.orientation.has('lock');
  } catch (_) {
    // Stariji browseri bez `screen.orientation` uopce.
    return false;
  }
}

Future<bool> lockLandscape() async {
  if (!canLockOrientation) return false;
  try {
    await web.window.screen.orientation.lock('landscape').toDart;
    return true;
  } catch (_) {
    // Desktop Chrome ima metodu ali odbija (`NotSupportedError`); Firefox
    // odbija bez fullscreena. Oboje znaci: idi na vizualnu rotaciju.
    return false;
  }
}

Future<void> unlockOrientation() async {
  try {
    web.window.screen.orientation.unlock();
  } catch (_) {}
}
