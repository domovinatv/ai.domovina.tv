/// Web implementacija muteanja — `<video>.muted`, ne `volume`.
///
/// Zašto ne `player.setVolume(0)`: na iOS-u `HTMLMediaElement.volume` NIJE
/// zapisiv (setter je no-op, getter uvijek vraća 1) jer Apple glasnoću drži
/// pod fizičkim tipkama uređaja. media_kit `setVolume` usput još i **skida**
/// `muted` flag prije nego postavi `volume`, pa je na iPhoneu efekt točno
/// suprotan od željenog — element ostane nemutiran i browser odbije autoplay.
///
/// `muted` property radi na svim browserima i jedini je koji WebKit gleda u
/// autoplay provjeri.
library;

import 'dart:js_interop';

import 'package:media_kit/media_kit.dart';
import 'package:web/web.dart' as web;

/// media_kitov `WebPlayer` drži javno polje `element` (HTMLVideoElement), ali
/// tip nije izvezen iz `package:media_kit/media_kit.dart` — do njega se dolazi
/// samo dinamički. Fallback je jedini `<video>` u dokumentu: naši ekrani drže
/// točno jedan media_kit player, a YouTube embed je cross-origin iframe pa se
/// njegov `<video>` ovdje uopće ne vidi.
web.HTMLVideoElement? _element(Player player) {
  try {
    final el = (player.platform as dynamic).element as JSAny?;
    if (el != null && el.isA<web.HTMLVideoElement>()) {
      return el as web.HTMLVideoElement;
    }
  } catch (_) {
    // Drukčija implementacija / promijenjen API — padamo na DOM pretragu.
  }
  final nodes = web.document.querySelectorAll('video');
  if (nodes.length == 1) {
    final node = nodes.item(0);
    if (node != null && node.isA<web.HTMLVideoElement>()) {
      return node as web.HTMLVideoElement;
    }
  }
  return null;
}

/// Postavlja `muted` na video element. Vraća `false` ako element nije nađen —
/// pozivatelj tada pada na `player.setVolume` (radi svugdje osim na iOS-u).
bool setElementMuted(Player player, bool muted) {
  final el = _element(player);
  if (el == null) return false;
  el.muted = muted;
  return true;
}

/// Stvarno stanje elementa; `null` ako element nije nađen.
bool? elementMuted(Player player) => _element(player)?.muted;
