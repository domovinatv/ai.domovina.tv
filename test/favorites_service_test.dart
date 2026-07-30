/// Ugovor lokalne police spremljenih epizoda (rail na naslovnici +
/// `/favorites`): redoslijed „najnoviji prvi", migracija sa starog v1 formata
/// i denorm metapodaci.
///
/// Remote (Supabase) grana se ovdje ne dira — bez prijavljenog klijenta
/// `_syncRemote` tiho izađe, pa testovi pokrivaju samo lokalnu putanju. U
/// `flutter test` je `kIsWeb == false`, pa servis ide kroz `SharedPreferences`;
/// web grana dijeli iste ključeve preko `local_prefs.dart`.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:domovina_ai/services/favorites_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FavoritesService.instance.debugReset());

  test('najnovije spremljeno je prvo', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final fav = FavoritesService.instance;

    await fav.toggle('prvi');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await fav.toggle('drugi');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await fav.toggle('treci');

    final ids = (await fav.entries()).map((e) => e.episodeId).toList();
    expect(ids, ['treci', 'drugi', 'prvi']);
  });

  test('toggle uklanja, remove je idempotentan', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final fav = FavoritesService.instance;

    expect(await fav.toggle('abc'), isTrue);
    expect(await fav.isFavorite('abc'), isTrue);
    expect(await fav.toggle('abc'), isFalse);
    expect(await fav.isFavorite('abc'), isFalse);

    await fav.remove('abc'); // ne smije puknuti ni notificirati bez potrebe
    expect(fav.count, 0);
  });

  test('denorm naslov/kanal prežive spremanje i čitanje', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await FavoritesService.instance
        .toggle('xyz', title: 'Naslov', channelName: 'Kanal');

    // Novi „session" nad istim diskom — čita se ono što je perzistirano.
    FavoritesService.instance.debugReset();
    final entry = (await FavoritesService.instance.entries()).single;
    expect(entry.episodeId, 'xyz');
    expect(entry.title, 'Naslov');
    expect(entry.channelName, 'Kanal');
    expect(entry.addedAt, isNotNull);
  });

  test('v1 zapisi (bez vremena) se migriraju i idu iza novih', () async {
    // Stari format: gola lista ID-eva pod `favorites_v1`.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'favorites_v1': jsonEncode(['stari_a', 'stari_b']),
    });
    final fav = FavoritesService.instance;

    expect(await fav.isFavorite('stari_a'), isTrue);
    await fav.toggle('novi');

    final ids = (await fav.entries()).map((e) => e.episodeId).toList();
    // Novi (ima vrijeme) prvi; legacy zadržavaju izvorni redoslijed iza njega.
    expect(ids, ['novi', 'stari_a', 'stari_b']);
  });
}
