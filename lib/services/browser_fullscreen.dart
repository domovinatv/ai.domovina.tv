/// Conditional-import wrapper za browser Fullscreen API.
///
/// media_kit fullscreen na webu pusha Flutter rutu + traži native browser
/// fullscreen, ali NE sluša `fullscreenchange` — kad korisnik pritisne Esc,
/// browser izađe iz fullscreena, a Flutter ruta ostane. Ovaj wrapper
/// omogućuje sinkronizaciju (vidi widgets/episode_video.dart).
///
/// Web build ucitava browser_fullscreen_web.dart (package:web), native
/// browser_fullscreen_stub.dart — isti pattern kao local_prefs.dart.
library;

import 'browser_fullscreen_web.dart'
    if (dart.library.io) 'browser_fullscreen_stub.dart' as platform;

/// True ako je neki element trenutno u native browser fullscreenu.
bool get isBrowserFullscreen => platform.isBrowserFullscreen;

/// Registrira `fullscreenchange` listener. Vraća funkciju za odjavu.
void Function() addFullscreenChangeListener(void Function() callback) =>
    platform.addFullscreenChangeListener(callback);
