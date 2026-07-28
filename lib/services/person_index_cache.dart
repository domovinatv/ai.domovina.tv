/// In-memory cache indeksa osoba (`GET /api/persons`), pandan
/// [channelCache] u `channel_cache.dart`.
///
/// Zašto zaseban cache umjesto polja u `ChannelCache`: virtualni kanal je
/// **drugi indeks** (odluka O1 u `docs/plans/virtualni-kanali.md`) — živi na
/// `mcp.domovina.ai`, ima HTTP-level cache (`max-age=900`) umjesto CDN
/// immutable + `?v=` bucketa, i ugovor `ChannelIndex`-a ostaje netaknut.
///
/// Router kreira nove ekrane pri svakoj navigaciji; singleton preživi.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/person_hub.dart';
import 'person_service.dart';

/// Globalni singleton — isti obrazac kao `channelCache`.
final personIndexCache = PersonIndexCache();

class PersonIndexCache extends ChangeNotifier {
  PersonIndex? _index;
  Future<PersonIndex?>? _inFlight;

  /// Zadnji pokušaj nije uspio (404 / mreža). Nije trajno stanje — sljedeći
  /// [loadIndex] pokušava ponovno, jer se `/api/persons` pojavi tek s F2.
  bool _failed = false;

  /// Cacheirani indeks — null dok nije učitan ILI ako dohvat nije uspio.
  PersonIndex? get index => _index;

  /// True čim je indeks jednom uspješno učitan.
  bool get loaded => _index != null;

  /// True kad je zadnji pokušaj pao — UI tada radi kao da osoba-kao-kanal ne
  /// postoji (graceful degradacija na stari backend).
  bool get unavailable => _failed && _index == null;

  /// Sve osobe iz indeksa; prazna lista dok indeks nije učitan.
  List<PersonSummary> get persons => _index?.persons ?? const [];

  /// Samo osobe koje smiju izgledati kao kanal — jedini popis koji katalog,
  /// home rail i TV lane smiju prikazati.
  List<PersonSummary> get virtualChannels =>
      _index?.virtualChannels ?? const [];

  PersonSummary? bySlug(String slug) => _index?.bySlug(slug);

  /// Učitaj indeks (jednom; višestruki pozivi dijele isti Future).
  /// Vraća `null` kad indeks nije dostupan — NIKAD ne baca.
  Future<PersonIndex?> loadIndex() {
    final cached = _index;
    if (cached != null) return Future<PersonIndex?>.value(cached);
    return _inFlight ??= _load();
  }

  Future<PersonIndex?> _load() async {
    try {
      final index = await PersonService.loadIndex();
      if (index == null) {
        _failed = true;
        notifyListeners();
        return null;
      }
      _index = index;
      _failed = false;
      notifyListeners();
      return index;
    } finally {
      // Neuspjeh se ne pamti kao konačan — dopusti retry pri sljedećoj
      // navigaciji (backend F2 može stići usred sesije).
      _inFlight = null;
    }
  }

  /// Test hook: ubaci indeks bez mreže.
  @visibleForTesting
  void debugSetIndex(PersonIndex? index) {
    _index = index;
    _failed = index == null;
    _inFlight = null;
    notifyListeners();
  }

  /// Test hook: vrati cache u početno stanje.
  @visibleForTesting
  void debugReset() {
    _index = null;
    _failed = false;
    _inFlight = null;
  }
}
