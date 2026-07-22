/// Defenderi za auth return-to kontrakt (2026-07-22, v2.0.103).
///
/// Štite dva svojstva koja budući refactori auth flowa NE smiju slomiti:
///  1. Prijava se vraća na ekran s kojeg je krenula (npr. /c/x/doniraj),
///     ne na homepage — a auth rute se nikad ne spremaju (callback loop).
///  2. localStorage vrijednost ne može postati open-redirect
///     ('//evil.com', 'https://…' → uvijek '/').
library;

import 'package:domovina_ai/services/auth_return_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('returnPathToSave', () {
    test('sprema path bez querya', () {
      expect(
        returnPathToSave(Uri.parse('https://domovina.ai/c/domovina-tv/doniraj')),
        '/c/domovina-tv/doniraj',
      );
    });

    test('sprema path + query', () {
      expect(
        returnPathToSave(
            Uri.parse('https://domovina.ai/c/x/support?uc=UC123&name=X')),
        '/c/x/support?uc=UC123&name=X',
      );
    });

    test('homepage se sprema kao /', () {
      expect(returnPathToSave(Uri.parse('https://domovina.ai/')), '/');
    });

    test('auth rute se NE spremaju (callback loop guard)', () {
      expect(
        returnPathToSave(Uri.parse('https://domovina.ai/auth/callback#x=1')),
        isNull,
      );
      expect(
        returnPathToSave(Uri.parse('https://domovina.ai/login-callback')),
        isNull,
      );
    });
  });

  group('sanitizeReturnPath', () {
    test('validna ruta prolazi netaknuta', () {
      expect(sanitizeReturnPath('/c/domovina-tv/doniraj'),
          '/c/domovina-tv/doniraj');
      expect(sanitizeReturnPath('/v/abc123?t=42'), '/v/abc123?t=42');
    });

    test('null / prazno / obrisano → homepage', () {
      expect(sanitizeReturnPath(null), '/');
      expect(sanitizeReturnPath(''), '/');
    });

    test('open-redirect pokušaji → homepage', () {
      expect(sanitizeReturnPath('https://evil.com/phish'), '/');
      expect(sanitizeReturnPath('//evil.com/phish'), '/');
      expect(sanitizeReturnPath('javascript:alert(1)'), '/');
      expect(sanitizeReturnPath('relative/path'), '/');
    });

    test('auth rute → homepage (callback ne redirecta sam na sebe)', () {
      expect(sanitizeReturnPath('/auth/callback'), '/');
      expect(sanitizeReturnPath('/login-callback'), '/');
    });
  });
}
