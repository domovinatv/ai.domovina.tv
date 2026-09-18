import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../../brand/app_brand.dart';
import '../../l10n/app_localizations.dart';
import '../../models/channel_index.dart';
import '../../services/local_prefs.dart';

const String _sortKey = 'channel_sort_v1';

/// Kljuc za korisnikov spremljeni redoslijed kanala (shuffle / custom order).
/// Dijeljen s home-om (vidi `home_screen.dart` `_channelOrderKey`).
const String _orderKey = 'channel_order';

/// Sort opcije za channel grid.
///
/// UI nudi [offered], ne [values]: [magisterium] postoji samo za brend s
/// domenskom ocjenom (`flags.domainScore`), a enum vrijednost ostaje zbog
/// spremljene preferencije i `applySortMode`.
enum ChannelSortMode {
  /// Po datumu zadnje epizode (najnoviji prvi).
  newest,

  /// Po broju epizoda (najvise prvi).
  mostEpisodes,

  /// Po prosjecnom Magisterium score-u (najvisi prvi, null na kraju).
  /// Nudi se samo kad je `flags.domainScore` upaljen — vidi [offered].
  magisterium,

  /// Abecedno po imenu (Hrvatska abeceda).
  alphabetical,

  /// Korisnikov spremljeni redoslijed (channel_order key) — uglavnom shuffle
  /// rezultat ili buduci drag-and-drop reorder.
  custom;

  /// Zadani mod kad preferencija ne postoji ili više nije dostupna.
  static const ChannelSortMode fallback = newest;

  /// Modovi koje aktivni brend nudi u UI-ju: svi osim [magisterium] kad je
  /// domenska ocjena ugašena.
  static List<ChannelSortMode> get offered => values
      .where((m) => m != magisterium || AppBrand.config.flags.domainScore)
      .toList();

  /// Je li mod dostupan aktivnom brendu.
  bool get isOffered => this != magisterium || AppBrand.config.flags.domainScore;

  String label(AppLocalizations l) {
    switch (this) {
      case ChannelSortMode.newest:
        return l.homeSortNewest;
      case ChannelSortMode.mostEpisodes:
        return l.homeSortMostEpisodes;
      case ChannelSortMode.magisterium:
        return l.homeSortMagisterium;
      case ChannelSortMode.alphabetical:
        return l.homeSortAlphabetical;
      case ChannelSortMode.custom:
        return l.homeSortCustom;
    }
  }
}

/// Primijeni sort mod na listu kanala. Custom koristi `customOrder` ako je
/// zadan (lista ID-jeva — ne-mapirani idu na kraj). Mod koji brend ne nudi
/// (npr. `magisterium` bez domenske ocjene) se tretira kao
/// [ChannelSortMode.fallback].
List<ChannelSummary> applySortMode(
  List<ChannelSummary> channels,
  ChannelSortMode mode, {
  List<String>? customOrder,
}) {
  if (!mode.isOffered) mode = ChannelSortMode.fallback;
  switch (mode) {
    case ChannelSortMode.newest:
      final list = List<ChannelSummary>.from(channels);
      list.sort((a, b) {
        final aDate = a.latestVideo?.date ?? '';
        final bDate = b.latestVideo?.date ?? '';
        return bDate.compareTo(aDate);
      });
      return list;
    case ChannelSortMode.mostEpisodes:
      final list = List<ChannelSummary>.from(channels);
      list.sort((a, b) => b.videoCount.compareTo(a.videoCount));
      return list;
    case ChannelSortMode.magisterium:
      final list = List<ChannelSummary>.from(channels);
      list.sort((a, b) {
        final aScore = a.avgMagisteriumScore;
        final bScore = b.avgMagisteriumScore;
        if (aScore == null && bScore == null) return 0;
        if (aScore == null) return 1;
        if (bScore == null) return -1;
        return bScore.compareTo(aScore);
      });
      return list;
    case ChannelSortMode.alphabetical:
      final list = List<ChannelSummary>.from(channels);
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    case ChannelSortMode.custom:
      if (customOrder == null || customOrder.isEmpty) return channels;
      final byId = {for (final ch in channels) ch.id: ch};
      final ordered = <ChannelSummary>[];
      for (final id in customOrder) {
        final ch = byId.remove(id);
        if (ch != null) ordered.add(ch);
      }
      ordered.addAll(byId.values);
      return ordered;
  }
}

/// Ucitaj spremljeni sort mode. Vraca null ako jos nije nikad spremljen
/// (tada caller moze migrirati: ako postoji legacy channel_order → custom).
///
/// Spremljeni mod koji aktivni brend ne nudi (npr. `magisterium` spremljen
/// prije nego je domenska ocjena ugašena) pada na [ChannelSortMode.fallback],
/// ne na `custom` — `custom` bi nad praznim `channel_order` ključem izazvao
/// shuffle koji korisnik nije tražio.
Future<ChannelSortMode?> loadSortMode() async {
  String? raw;
  if (kIsWeb) {
    raw = getLocalStorageString(_sortKey);
  } else {
    final prefs = await SharedPreferences.getInstance();
    raw = prefs.getString(_sortKey);
  }
  if (raw == null) return null;
  final mode = ChannelSortMode.values
      .firstWhere((m) => m.name == raw, orElse: () => ChannelSortMode.custom);
  return mode.isOffered ? mode : ChannelSortMode.fallback;
}

Future<void> saveSortMode(ChannelSortMode mode) async {
  if (kIsWeb) {
    setLocalStorageString(_sortKey, mode.name);
  } else {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortKey, mode.name);
  }
}

/// Ucitaj korisnikov spremljeni redoslijed kanala (ID lista). null ako nikad
/// nije spremljen. Web koristi localStorage (SharedPreferences puca u release
/// dart2js buildu — vidi CLAUDE.md).
Future<List<String>?> loadCustomOrder() async {
  if (kIsWeb) {
    final raw = getLocalStorageString(_orderKey);
    if (raw == null || raw.isEmpty) return null;
    return raw.split(',');
  }
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_orderKey);
}

Future<void> saveCustomOrder(List<String> ids) async {
  if (kIsWeb) {
    setLocalStorageString(_orderKey, ids.join(','));
  } else {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, ids);
  }
}
