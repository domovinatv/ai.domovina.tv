import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool prefersReducedData() {
  try {
    final conn = (web.window.navigator as JSObject).getProperty<JSObject?>(
      'connection'.toJS,
    );
    if (conn == null) return false;
    final saveData = conn.getProperty<JSBoolean?>('saveData'.toJS)?.toDart;
    if (saveData == true) return true;
    final type = conn.getProperty<JSString?>('effectiveType'.toJS)?.toDart;
    return type == '2g' || type == 'slow-2g';
  } catch (_) {
    return false;
  }
}
