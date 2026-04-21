/// Conditional-import wrapper za browser localStorage.
/// Web build ucitava local_prefs_web.dart (package:web), native local_prefs_stub.dart.
/// Bez ove indirekcije Android/iOS build puca jer package:web/src/helpers/cross_origin.dart
/// koristi dart:js_interop tipove koji ne resolvaju na VM targetima.
library;

import 'local_prefs_web.dart'
    if (dart.library.io) 'local_prefs_stub.dart' as platform;

String? getLocalStorageString(String key) =>
    platform.getLocalStorageString(key);

void setLocalStorageString(String key, String value) =>
    platform.setLocalStorageString(key, value);
