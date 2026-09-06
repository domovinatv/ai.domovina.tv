import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Pamćenje vertikalne scroll pozicije po ruti.
///
/// **Ovo NIJE glavni mehanizam za vraćanje scrolla.** Glavni je `push` iz
/// `lib/router/nav.dart`: ruta ispod ostaje živa pa njezin `ScrollPosition`
/// nikad ne ode. Ovaj sloj pokriva samo slučajeve u kojima ekran STVARNO mora
/// nastati iznova:
///
///  - dolazak izvana na `/v/<id>` pa ← na `/` (nema se što popati),
///  - hard refresh / povratak u tab nakon zatvaranja,
///  - `go('/')` s breadcrumba „Početna", koji je namjerno reset stoga.
///
/// Pozicije žive samo u memoriji procesa — namjerno. Perzistiranje bi značilo
/// da korisnik nakon dana pauze doskoči na sredinu liste koja se u međuvremenu
/// promijenila.
class ScrollMemory {
  ScrollMemory._();
  static final ScrollMemory instance = ScrollMemory._();

  final Map<String, double> _offsets = {};

  /// Ključ MORA nositi query string: `/channels` i `/channels?prikaz=osobe` su
  /// dva prikaza iste rute (odluka O9 u docs/plans/virtualni-kanali.md) i imaju
  /// dvije nezavisne pozicije. Isti razlog zbog kojeg ruter već ima različit
  /// `ValueKey` po prikazu.
  double? read(String key) => _offsets[key];

  void save(String key, double offset) {
    if (offset <= 0) {
      _offsets.remove(key);
      return;
    }
    _offsets[key] = offset;
  }

  void clear(String key) => _offsets.remove(key);

  @visibleForTesting
  void clearAll() => _offsets.clear();
}

/// Zakači pamćenje pozicije na jedan scrollable.
///
/// Spremanje je debounceano (scroll notifikacije lete ~60×/s); vraćanje čeka da
/// sadržaj naraste do spremljenog offseta.
///
/// **Rule (tri detalja bez kojih ovo ne radi):**
///  1. `jumpTo`, ne `animateTo` — animacija na povratku izgleda kao da je
///     stranica sama otišla dolje.
///  2. Čekaj `maxScrollExtent >= offset`. Naslovnica visinu dobiva u više
///     asinkronih koraka, pa bi rani `jumpTo` bio clampan na visinu skeletona i
///     tiho se izgubio. Odustajemo nakon [_restoreTimeout] — bolje vrh nego
///     skok u pogrešno mjesto nakon što korisnik već čita.
///  3. Ne diraj poziciju ako je korisnik u međuvremenu sam scrollao.
class ScrollRestorer extends StatefulWidget {
  final String storageKey;
  final ScrollController controller;
  final Widget child;

  const ScrollRestorer({
    super.key,
    required this.storageKey,
    required this.controller,
    required this.child,
  });

  @override
  State<ScrollRestorer> createState() => _ScrollRestorerState();
}

class _ScrollRestorerState extends State<ScrollRestorer> {
  static const _saveDebounce = Duration(milliseconds: 250);
  static const _restoreTimeout = Duration(seconds: 2);

  Timer? _saveTimer;
  bool _restoreDone = false;
  bool _userScrolled = false;
  DateTime? _restoreStartedAt;

  @override
  void initState() {
    super.initState();
    final saved = ScrollMemory.instance.read(widget.storageKey);
    if (saved == null || saved <= 0) {
      _restoreDone = true;
    } else {
      _restoreStartedAt = DateTime.now();
      SchedulerBinding.instance.addPostFrameCallback((_) => _tryRestore(saved));
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // Zadnja pozicija ide u memoriju i kad se ekran ruši prije nego debounce
    // istekne — inače se izgubi baš zadnji korisnikov pomak.
    if (widget.controller.hasClients) {
      ScrollMemory.instance
          .save(widget.storageKey, widget.controller.position.pixels);
    }
    super.dispose();
  }

  void _tryRestore(double target) {
    if (!mounted || _restoreDone) return;

    // Korisnik je prestigao restore — njegov pomak je jači signal.
    if (_userScrolled) {
      _restoreDone = true;
      return;
    }

    final started = _restoreStartedAt;
    if (started != null &&
        DateTime.now().difference(started) > _restoreTimeout) {
      _restoreDone = true;
      return;
    }

    if (!widget.controller.hasClients) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _tryRestore(target));
      return;
    }

    final position = widget.controller.position;
    if (position.maxScrollExtent >= target) {
      position.jumpTo(target);
      _restoreDone = true;
      return;
    }

    // Sadržaj još raste — probaj u sljedećem frameu.
    SchedulerBinding.instance.addPostFrameCallback((_) => _tryRestore(target));
  }

  bool _onNotification(ScrollNotification n) {
    if (n.depth != 0) return false; // ignoriraj ugniježđene (horizontalne) railove
    if (n is UserScrollNotification && _restoreDone == false) {
      _userScrolled = true;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      if (!mounted || !widget.controller.hasClients) return;
      ScrollMemory.instance
          .save(widget.storageKey, widget.controller.position.pixels);
    });
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: widget.child,
      );
}
