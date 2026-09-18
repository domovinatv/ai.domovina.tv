/// Rotacijski („virtualni") fullscreen — putanja **C** iz T4.
///
/// Koristi se ondje gdje pravi landscape nije moguć: iPhone Safari i iOS Chrome
/// (`screen.orientation` bez `lock` metode), desktop Chrome u device toolbaru
/// (`lock` odbije), i općenito svaki portretni viewport gdje A/B padnu. Slika se
/// **vizualno** rotira 90° u smjeru kazaljke preko cijelog portretnog viewporta.
///
/// **Hit-testing je dokazan, ne pretpostavljen** (`test/rotated_fullscreen_test.dart`):
/// `RotatedBox` transformira i pointer događaje — tap na mjestu gdje je meta
/// nacrtana pogađa, a delta poteza se preslikava u prostor djeteta pa pravi
/// `Slider` (seek bar) prati potez bez ručnog preračunavanja koordinata.
///
/// Zašto vlastita ruta a ne media_kitova: njihova (`.../methods/fullscreen.dart`)
/// nema hook za ubacivanje rotacije između `Material` korijena i `Video`
/// widgeta.
library;

import 'package:flutter/material.dart';

/// Otvara rotirani fullscreen preko root navigatora.
///
/// [builder] dobiva `exit` callback — istu funkciju koristi gumb u kontrolama,
/// Esc na webu i sve ostalo što ne ide preko sistemskog Backa (Back radi sam,
/// obična ruta se popa; zato ovdje nema `PopScope` koji bi to samo presretao).
///
/// [onClosed] se zove kad ruta stvarno nestane s ekrana — **bilo kojim** putem
/// (gumb, Back, Esc, `Navigator.pop` odnekud drugdje). Ide kroz `dispose` rute,
/// ne kroz `await` na push future, jer je jedino tako zajamčeno da se pozove i
/// kad rutu skine netko treći. Pozivatelj tu vraća playback i izlazi iz
/// browser fullscreena.
Future<void> showRotatedFullscreen({
  required BuildContext context,
  required Widget Function(BuildContext context, VoidCallback exit) builder,
  void Function(VoidCallback exit)? onOpened,
  VoidCallback? onClosed,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  late final PageRouteBuilder<void> route;

  void exit() {
    if (!route.isActive) return;
    // `pop` kad je naša ruta na vrhu (normalno), `removeRoute` ako je netko
    // nešto pushao iznad — inače bismo zatvorili tuđu rutu.
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  route = PageRouteBuilder<void>(
    opaque: true,
    barrierDismissible: false,
    // Instant, kao i ostatak routinga u appu (main.dart, `Duration.zero`).
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (routeContext, _, _) => _RotatedFullscreenPage(
      onDisposed: onClosed,
      child: builder(routeContext, exit),
    ),
  );

  // Prije pusha, da pozivatelj ima `exit` u ruci i van gradnje widgeta (Esc
  // listener i ponovni tap na gumb moraju moći zatvoriti rutu).
  onOpened?.call(exit);

  return navigator.push(route);
}

class _RotatedFullscreenPage extends StatefulWidget {
  const _RotatedFullscreenPage({required this.child, this.onDisposed});

  final Widget child;
  final VoidCallback? onDisposed;

  @override
  State<_RotatedFullscreenPage> createState() => _RotatedFullscreenPageState();
}

class _RotatedFullscreenPageState extends State<_RotatedFullscreenPage> {
  @override
  void dispose() {
    widget.onDisposed?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotatedFullscreenView(child: widget.child);
}

/// Sadržaj rotirane rute — izdvojeno iz rute da je testabilno bez navigatora.
class RotatedFullscreenView extends StatelessWidget {
  const RotatedFullscreenView({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final portrait = mq.size.height > mq.size.width;

    // Ako je viewport već landscape (korisnik je fizički rotirao uređaj s
    // isključenom bravom, ili je ovo ipak široki ekran), rotacija bi sliku
    // okrenula na krivu stranu — onda samo ispuni ekran.
    if (!portrait) {
      return _surface(child);
    }

    // Dijete radi u landscape prostoru (`RotatedBox` zamijeni constraintove), pa
    // mu i `MediaQuery` mora govoriti landscape — inače `MediaQuery.sizeOf`
    // unutra laže, a safe-area insete bi primijenilo na krive rubove.
    //
    // Preslikavanje rubova za 90° u smjeru kazaljke (dokazano u testu:
    // gornji lijevi kut djeteta izlazi u gornjem desnom kutu ekrana):
    //   lijevi rub djeteta → gornji rub ekrana
    //   gornji rub djeteta → desni rub ekrana
    //   desni rub djeteta  → donji rub ekrana
    //   donji rub djeteta  → lijevi rub ekrana
    EdgeInsets rotate(EdgeInsets i) => EdgeInsets.only(
          left: i.top,
          top: i.right,
          right: i.bottom,
          bottom: i.left,
        );

    return _surface(
      MediaQuery(
        data: mq.copyWith(
          size: Size(mq.size.height, mq.size.width),
          padding: rotate(mq.padding),
          viewPadding: rotate(mq.viewPadding),
          // Tipkovnice nema u fullscreen videu; rotirani inset bi samo gurao
          // kontrole u prazno.
          viewInsets: EdgeInsets.zero,
        ),
        child: RotatedBox(quarterTurns: 1, child: child),
      ),
    );
  }

  Widget _surface(Widget content) => Material(
        color: Colors.black,
        child: SizedBox.expand(child: content),
      );
}
