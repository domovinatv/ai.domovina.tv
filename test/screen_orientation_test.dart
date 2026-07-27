/// Čuva **uvjetni import** brave orijentacije (T4).
///
/// Test je namjerno mršav: sama činjenica da se prevede dokazuje da je na
/// nativeu/VM-u izabran `screen_orientation_stub.dart`, a ne web putanja — da
/// gate ikad krene na `dart.library.html` ili se okrene, `package:web` bi ušao
/// u native prevođenje i ovo bi puklo. Wasm stranu istog gatea pokriva
/// `flutter build web --wasm`.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/services/screen_orientation.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('native mobile zna zaključati orijentaciju (SystemChrome putanja)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(canLockOrientation, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(canLockOrientation, isTrue);
  });

  test('desktop native ne dira orijentaciju — fullscreen ostaje kakav je bio',
      () {
    for (final platform in const [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(canLockOrientation, isFalse, reason: '$platform');
    }
  });

  test('lockLandscape na desktopu javi false → pozivatelj ide na rotaciju',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(await lockLandscape(), isFalse);
    // Bez brave nema ni otključavanja (ne smije baciti).
    await unlockOrientation();
  });
}
