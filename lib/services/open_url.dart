import 'package:flutter/foundation.dart' show kIsWeb;
import 'open_url_web.dart' if (dart.library.io) 'open_url_native.dart'
    as platform;

/// Opens a URL — uses window.open on web (Skwasm compatible),
/// url_launcher on native.
void openUrl(String url) {
  if (kIsWeb) {
    platform.openUrlImpl(url);
  } else {
    platform.openUrlImpl(url);
  }
}
