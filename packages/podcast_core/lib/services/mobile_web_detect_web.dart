import 'package:web/web.dart' as web;

/// Vraća 'ios' | 'android' | '' na temelju browser userAgent-a.
/// Tehnika preuzeta iz smpltsk/web/redirect.html detekcije.
String mobileWebOs() {
  final ua = web.window.navigator.userAgent;
  // iPadOS 13+ se lažno predstavlja kao "Macintosh" — dopuni provjerom
  // touch pointa da uhvatimo i iPad u desktop-mode Safariju.
  final isIOS = RegExp(r'iPad|iPhone|iPod').hasMatch(ua) ||
      (ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1);
  if (isIOS) return 'ios';
  if (ua.contains('Android')) return 'android';
  return '';
}

/// True ako je web već pokrenut kao instalirani PWA (display-mode: standalone).
/// U tom slučaju ne nudimo preuzimanje native aplikacije.
bool isStandalonePwa() {
  try {
    return web.window.matchMedia('(display-mode: standalone)').matches;
  } catch (_) {
    return false;
  }
}

/// True za Safari na iOS-u. Apple Smart App Banner (apple-itunes-app meta u
/// index.html) renderira SAMO Safari, pa u tom slučaju NE prikazujemo i
/// Flutter snackbar (izbjegavamo dupli banner). iOS Chrome/Firefox/Edge nose
/// CriOS/FxiOS/EdgiOS u userAgentu — tamo Smart App Banner ne postoji pa
/// snackbar preuzima ulogu.
bool isIosSafari() {
  final ua = web.window.navigator.userAgent;
  final isOtherBrowser =
      RegExp(r'CriOS|FxiOS|EdgiOS|OPiOS|GSA').hasMatch(ua);
  return ua.contains('Safari') && !isOtherBrowser;
}
