import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/channel_index.dart';
import '../../services/local_prefs.dart';

const String _sortKey = 'channel_sort_v1';

/// Sort opcije za channel grid.
enum ChannelSortMode {
  /// Po datumu zadnje epizode (najnoviji prvi).
  newest,

  /// Po broju epizoda (najvise prvi).
  mostEpisodes,

  /// Po prosjecnom Magisterium score-u (najvisi prvi, null na kraju).
  magisterium,

  /// Abecedno po imenu (Hrvatska abeceda).
  alphabetical,

  /// Korisnikov spremljeni redoslijed (channel_order key) — uglavnom shuffle
  /// rezultat ili buduci drag-and-drop reorder.
  custom;

  String get label {
    switch (this) {
      case ChannelSortMode.newest:
        return 'Najnoviji';
      case ChannelSortMode.mostEpisodes:
        return 'Najviše epizoda';
      case ChannelSortMode.magisterium:
        return 'Magisterium score';
      case ChannelSortMode.alphabetical:
        return 'Abecedno';
      case ChannelSortMode.custom:
        return 'Moj redoslijed';
    }
  }
}

/// Primijeni sort mod na listu kanala. Custom koristi `customOrder` ako je
/// zadan (lista ID-jeva — ne-mapirani idu na kraj).
List<ChannelSummary> applySortMode(
  List<ChannelSummary> channels,
  ChannelSortMode mode, {
  List<String>? customOrder,
}) {
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
Future<ChannelSortMode?> loadSortMode() async {
  String? raw;
  if (kIsWeb) {
    raw = getLocalStorageString(_sortKey);
  } else {
    final prefs = await SharedPreferences.getInstance();
    raw = prefs.getString(_sortKey);
  }
  if (raw == null) return null;
  return ChannelSortMode.values
      .firstWhere((m) => m.name == raw, orElse: () => ChannelSortMode.custom);
}

Future<void> saveSortMode(ChannelSortMode mode) async {
  if (kIsWeb) {
    setLocalStorageString(_sortKey, mode.name);
  } else {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortKey, mode.name);
  }
}
