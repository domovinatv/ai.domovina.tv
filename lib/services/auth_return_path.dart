/// Povratna ruta nakon full-page auth redirecta (OAuth / magic link).
/// Čista logika bez ovisnosti — izdvojena da bude unit-testabilna kao
/// defender protiv regresija (vidi test/auth_return_path_test.dart).
///
/// Kontrakt (uveden 2026-07-22, v2.0.103 — prije je login uvijek završavao
/// na homepageu, loš UX s /c/x/doniraj i sličnih ekrana):
///  1. Prije napuštanja stranice sprema se path+query trenutne rute
///     ([returnPathToSave]); auth rute se NE spremaju (callback loop).
///  2. Po povratku se prihvaća samo same-origin apsolutni path
///     ([sanitizeReturnPath]) — localStorage vrijednost NIKAD ne smije
///     postati open-redirect vektor ('//evil.com', 'https://…').
library;

/// localStorage ključ — ruta (path+query) s koje je prijava krenula. Piše ga
/// AuthService prije OAuth/magic-link redirecta, čita AuthCallbackScreen.
/// Briše se postavljanjem na prazan string.
const String authReturnToKey = 'auth_return_to';

/// Auth rute nikad nisu povratna destinacija — callback koji redirecta na
/// samog sebe zavrtio bi spinner u loop.
bool _isAuthRoute(String path) =>
    path.startsWith('/auth/') || path.startsWith('/login-callback');

/// Path+query koji treba spremiti prije redirecta, ili null ako se s [base]
/// (u praksi Uri.base) ne sprema ništa jer je korisnik već na auth ruti.
String? returnPathToSave(Uri base) {
  final path = base.path;
  if (_isAuthRoute(path)) return null;
  final query = base.hasQuery ? '?${base.query}' : '';
  return '$path$query';
}

/// Validira spremljenu vrijednost iz localStoragea — vraća sigurnu
/// destinaciju ili '/'. Prihvaća samo apsolutni same-origin path: mora
/// počinjati s '/', ne smije biti '//host' ni auth ruta.
String sanitizeReturnPath(String? saved) {
  if (saved == null ||
      saved.isEmpty ||
      !saved.startsWith('/') ||
      saved.startsWith('//') ||
      _isAuthRoute(saved)) {
    return '/';
  }
  return saved;
}
