import 'package:web/web.dart' as web;

/// Update address bar bez triggera router refresha.
///
/// replaceState NE fira popstate event, pa go_router ostaje nesvjestan
/// promjene — Flutter widget tree se ne rebuilda, player nastavlja raditi.
/// (Push bi bio loš — back button bi bio puno timestampa.)
///
/// [langSuffix]: '/en' kad je korisnik na engleskom; null ili '' za HR.
/// Stavi se NAKON timestamp segmenta da social crawleri vide stabilan
/// path-based URL (query parameters get droppani u WhatsApp/Facebook preview).
void replaceTimestampImpl(String basePath, int? seconds, {String? langSuffix}) {
  final ts = (seconds != null && seconds > 0) ? '/t/$seconds' : '';
  final lang = (langSuffix != null && langSuffix.isNotEmpty) ? langSuffix : '';
  final url = '$basePath$ts$lang';
  // Treći arg je URL — relativni je OK, browser ga resolva u trenutni origin.
  web.window.history.replaceState(null, '', url);
}
