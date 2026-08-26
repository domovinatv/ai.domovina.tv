import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// True kad stranica radi u **cross-origin izolaciji** (`COOP: same-origin` +
/// `COEP`). Naš worker te headere šalje namjerno — bez njih Flutter ne dobije
/// `SharedArrayBuffer` pa umjesto `skwasm_heavy.wasm` (raster na zasebnoj niti)
/// učita jednodretveni `skwasm.wasm` i rasterizira na glavnoj niti. Vidi
/// `docs/web-delivery-and-rendering.md` §1.
bool get _crossOriginIsolated =>
    globalContext.getProperty<JSBoolean?>('crossOriginIsolated'.toJS)?.toDart ??
    false;

/// True kad browser podržava **credentialless iframe** (Chrome/Edge 110+).
///
/// To je jedini način da dokument pod COEP-om ugradi tuđi iframe koji sam ne
/// šalje COEP — a YouTube ga ne šalje. Bez toga browser odbije frame s
/// „www.youtube-nocookie.com refused to connect".
bool get _credentiallessSupported {
  final ctor = globalContext.getProperty<JSObject?>('HTMLIFrameElement'.toJS);
  final proto = ctor?.getProperty<JSObject?>('prototype'.toJS);
  return proto?.has('credentialless') ?? false;
}

bool? _supportedCache;

/// Smije li se YouTube uopće ugraditi u ovu stranicu.
///
/// **Rule**: ovo NIJE samo „jesmo li na webu". Pod cross-origin izolacijom
/// (koju naš `web/_worker.js` uključuje za skwasm) tuđi iframe prolazi SAMO uz
/// `credentialless` atribut, koji podržavaju Chrome i Edge — Safari i Firefox
/// ne. Ondje se embed ne smije ni ponuditi: korisniku bi se otvorila crna ploha
/// s „refused to connect" umjesto videa. Facade tada otvori youtube.com.
///
/// Izmjereno 26.8.2026.: prva izvedba je vraćala `true` bezuvjetno, pa je embed
/// na produkciji bio crn — a isti je kvar tiho nosio i postojeći „YouTube mode"
/// gumb u `video_panel.dart`, koji je zbog toga bio neupotrebljiv otkad postoji.
bool get supported =>
    _supportedCache ??= !_crossOriginIsolated || _credentiallessSupported;

/// Registrirani viewType-ovi — factory se smije registrirati samo jednom.
final Set<String> _registeredViewTypes = <String>{};

Widget buildYouTubeEmbed({
  required String videoId,
  required int startSeconds,
}) {
  final viewType = 'domovina-yt-embed-$videoId-$startSeconds';
  if (_registeredViewTypes.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final src = Uri.https(
        'www.youtube-nocookie.com',
        '/embed/$videoId',
        <String, String>{
          'autoplay': '1',
          if (startSeconds > 0) 'start': '$startSeconds',
          'rel': '0',
          'playsinline': '1',
          'hl': 'hr',
          'color': 'white',
        },
      ).toString();
      final iframe = web.HTMLIFrameElement()
        // MORA prije `src`: atribut se čita pri pokretanju navigacije, pa ga
        // postavljanje nakon toga više ne bi spasilo od COEP odbijanja.
        ..setAttribute('credentialless', '')
        ..src = src
        ..allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture'
        ..allowFullscreen = true;
      iframe.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%';
      return iframe;
    });
  }
  return HtmlElementView(viewType: viewType);
}
