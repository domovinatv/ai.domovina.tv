/// Predučitavanje epizoda na koje će korisnik VJEROJATNO kliknuti — ne svih
/// na koje može.
///
/// Svaka epizoda na naslovnici je klikabilna (30–50 njih), a ekran epizode
/// danas traži ~18 datoteka od kojih ih tipično postoji 7. Predučitati sve bilo
/// bi ~1 000 zahtjeva i 3–5 MB uz naslovnicu, na sporoj mreži upravo ondje gdje
/// boli. Zato samo dva okidača:
///
/// - **mirovanje**: kad se hero izbor latcha, prva epizoda hera i prve iz
///   „Nastavi slušati" ([idle]);
/// - **namjera**: miš iznad kartice ili prst na njoj ([intent]) — dodir
///   prethodi `onTap`-u za ~100–300 ms, hover i više.
///
/// Dohvaća se samo ono što treba za prvi prikaz
/// ([DataService.prefetchFirstPaint], ~35 KB brotli po epizodi), najviše
/// [_maxConcurrent] epizode odjednom da ne guši slike naslovnice, i ništa kad
/// korisnik štedi podatke ([prefersReducedData]). Odgovori idu u
/// `DataService`-ovu memoriju (i na nativeu u disk cache, pa i offline).
///
/// Mjerenja i plan: `docs/2026-10-08-brzina-ucitavanja-naslovnice.md` §8.
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../main.dart' show log;
import 'data_service.dart';
import 'network_hints.dart';

class EpisodePrefetch {
  EpisodePrefetch._();
  static final EpisodePrefetch instance = EpisodePrefetch._();

  static const int _maxConcurrent = 2;

  /// Gornja granica po sesiji — zaštita od korisnika koji mišem prijeđe preko
  /// cijele mreže kartica.
  static const int _maxPerSession = 40;

  final Set<String> _seen = {};
  final Queue<String> _queue = Queue();
  int _running = 0;

  /// Okidač s namjerom (hover, pointer down): ide na čelo reda.
  void intent(String youtubeId) => _enqueue(youtubeId, front: true);

  /// Okidač u mirovanju: ide na kraj reda, iza svake namjere.
  void idle(Iterable<String> youtubeIds) {
    for (final id in youtubeIds) {
      _enqueue(id, front: false);
    }
  }

  void _enqueue(String id, {required bool front}) {
    if (id.isEmpty || _seen.contains(id)) return;
    if (_seen.length >= _maxPerSession) return;
    if (prefersReducedData()) return;
    _seen.add(id);
    front ? _queue.addFirst(id) : _queue.addLast(id);
    _pump();
  }

  void _pump() {
    while (_running < _maxConcurrent && _queue.isNotEmpty) {
      final id = _queue.removeFirst();
      _running++;
      DataService(youtubeId: id).prefetchFirstPaint().whenComplete(() {
        _running--;
        if (kDebugMode) log('EpisodePrefetch: $id');
        _pump();
      });
    }
  }

  @visibleForTesting
  void resetForTest() {
    _seen.clear();
    _queue.clear();
    _running = 0;
  }
}
