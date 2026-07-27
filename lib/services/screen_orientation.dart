/// Conditional-import wrapper za bravu orijentacije zaslona.
///
/// Fullscreen videa u portretu traži landscape sliku. Tri platforme daju tri
/// razine mogućnosti (plan `docs/plans/2026-07-27-playback-overhaul.md`, T4):
///
///  - **native iOS/Android** — `SystemChrome.setPreferredOrientations` forsira
///    pravi landscape i **probija sistemsku bravu rotacije** (odluka D3);
///  - **web gdje ide** (Android Chrome) — `screen.orientation.lock('landscape')`,
///    ali **samo nakon** `requestFullscreen`;
///  - **web gdje ne ide** (iPhone Safari i iOS Chrome — `screen.orientation`
///    postoji, ali bez `lock` metode; desktop Chrome — `lock` postoji pa
///    `canLockOrientation` javi `true`, ali poziv odbije obećanje) → ostaje
///    vizualna rotacija, `widgets/rotated_fullscreen.dart`.
///
/// Zato [lockLandscape] vraća `bool`: `false` znači „ovdje pravi landscape nije
/// moguć, idi na vizualnu rotaciju". Feature-test sam nije dovoljan.
///
/// Gate je **`dart.library.js_interop`**, ne `dart.library.html` — potonji ne
/// postoji u `--wasm` buildu pa bi ondje pao na stub (poznata zamka, vidi
/// `docs/` i memoriju o wasm uvjetnim importima).
library;

import 'screen_orientation_stub.dart'
    if (dart.library.js_interop) 'screen_orientation_web.dart' as platform;

/// True ako platforma u principu zna zaključati orijentaciju. Na webu je to
/// samo feature-test (`'lock' in screen.orientation`) — desktop Chrome ga
/// prolazi a poziv svejedno odbije, pa je pravi odgovor uvijek [lockLandscape].
bool get canLockOrientation => platform.canLockOrientation;

/// Zaključa zaslon u landscape. Vraća true samo ako je brava stvarno legla.
///
/// Na webu **mora** biti pozvano nakon ulaska u browser fullscreen — inače
/// Chrome odbije s `NotSupportedError`.
Future<bool> lockLandscape() => platform.lockLandscape();

/// Vraća orijentaciju i sistemske trake na zatečeno stanje. Zvati samo ako je
/// [lockLandscape] uspio — inače nepotrebno mijenja stanje koje nismo dirali.
Future<void> unlockOrientation() => platform.unlockOrientation();
