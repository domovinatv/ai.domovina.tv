import 'package:web/web.dart' as web;

String? getLocalStorageString(String key) {
  try {
    final raw = web.window.localStorage.getItem(key);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  } catch (_) {
    return null;
  }
}

void setLocalStorageString(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}
