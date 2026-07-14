/// Conditional-import wrapper za detekciju mobilnog browsera na webu.
/// Web build učitava mobile_web_detect_web.dart (package:web), native stub.
/// Ista indirekcija kao local_prefs.dart — package:web tipovi ne resolvaju na
/// VM targetima pa native mora ići na stub.
library;

import 'mobile_web_detect_web.dart'
    if (dart.library.io) 'mobile_web_detect_stub.dart' as platform;

/// 'ios' | 'android' | '' — prazan string na desktopu i u native buildu.
String mobileWebOs() => platform.mobileWebOs();

/// True ako je web pokrenut kao instalirani PWA (standalone display mode).
bool isStandalonePwa() => platform.isStandalonePwa();

/// True za Safari na iOS-u (gdje Apple Smart App Banner već pokriva promociju).
bool isIosSafari() => platform.isIosSafari();
