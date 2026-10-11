/// Screenshotovi sekcija čekaju da video krene.
///
/// Epizoda ima i po 26+ screenshotova (PNG 1920×1080, ~1,3 MB svaki — 33 MB za
/// `PPXbSP14H4Y`), a članak gradi sve sekcije odjednom (`sectionKeys` za skok
/// na sekciju), pa su svi kretali u istom trenutku kad i video i gušili ga na
/// sporoj vezi. Ekran epizode zato pri otvaranju zadrži sve osim prioritetnih
/// (prva sekcija + sekcija na koju vodi `/t/<sec>`) i pusti ih kad player javi
/// `playing`, kad otvaranje padne, ili najkasnije nakon [_maxHold].
///
/// Singleton jer kartice sekcija žive u tri različita stabla (obični,
/// paralelni i TV prikaz) — isti razlog kao `PlaybackSpeed`. Ekran koji nikad
/// ne zove [hold] (jednostavni prikaz, TV) ne odgađa ništa.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

class DeferredScreenshots extends ChangeNotifier {
  DeferredScreenshots._();
  static final DeferredScreenshots instance = DeferredScreenshots._();

  static const _maxHold = Duration(seconds: 8);

  bool _held = false;
  Set<String> _priority = const {};
  Timer? _timer;

  /// Smije li se screenshot sekcije [timestamp] (`HH:MM:SS`) već učitati.
  bool allows(String timestamp) => !_held || _priority.contains(timestamp);

  /// Zadrži sve screenshotove osim [priority] dok se ne pozove [release].
  void hold({required Set<String> priority}) {
    _timer?.cancel();
    _held = true;
    _priority = priority;
    _timer = Timer(_maxHold, release);
    notifyListeners();
  }

  void release() {
    _timer?.cancel();
    _timer = null;
    if (!_held) return;
    _held = false;
    notifyListeners();
  }
}
