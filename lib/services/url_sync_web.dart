import 'package:web/web.dart' as web;

/// Update address bar bez triggera router refresha.
///
/// replaceState NE fira popstate event, pa go_router ostaje nesvjestan
/// promjene — Flutter widget tree se ne rebuilda, player nastavlja raditi.
/// (Push bi bio loš — back button bi bio puno timestampa.)
void replaceTimestampImpl(String basePath, int? seconds) {
  final url = (seconds != null && seconds > 0)
      ? '$basePath/t/$seconds'
      : basePath;
  // Treći arg je URL — relativni je OK, browser ga resolva u trenutni origin.
  web.window.history.replaceState(null, '', url);
}
