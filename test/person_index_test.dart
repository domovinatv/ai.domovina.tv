import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:domovina_ai/models/person_hub.dart';
import 'package:domovina_ai/services/person_channel_flag.dart';
import 'package:domovina_ai/services/person_index_cache.dart';

/// Kontrakt indeksa osoba (`GET mcp.domovina.ai/api/persons`, §4.1 plana
/// `docs/plans/virtualni-kanali.md`) + cache i feature flag.
///
/// Fixturei su jedini izvor istine dok F2 ne ode u produkciju — endpoint danas
/// vraća 404, pa je graceful degradacija dio ugovora, ne nice-to-have.
Map<String, dynamic> _fixture(String name) => jsonDecode(
      File('test/fixtures/$name').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  group('PersonIndex.fromJson', () {
    late PersonIndex index;

    setUp(() => index = PersonIndex.fromJson(_fixture('persons_index.json')));

    test('parsira fixture iz §4.1 bez gubitka', () {
      expect(index.version, '1.0');
      expect(index.personCount, 3);
      expect(index.persons.length, 3);

      final msr = index.bySlug('marijana-sarolic-robic')!;
      expect(msr.name, 'Marijana Šarolić Robić');
      expect(msr.episodeCount, 17);
      expect(msr.channelCount, 17);
      expect(msr.totalDurationSeconds, 49151);
      expect(msr.durationDisplay, '13h 39m');
      expect(msr.avatarUrl, isNull);
      expect(msr.avgMagisteriumScore, isNull);
      expect(msr.firstYear, 2020);
      expect(msr.lastYear, 2026);
      expect(msr.isVirtualChannel, isTrue);
      expect(msr.latestEpisode!.youtubeId, 'bkp-0X4aG9E');
      expect(msr.latestEpisode!.date, '2026-06-24');
      // Person slug ide DOSLOVNO — bez `-`↔`_` transformacije kanala.
      expect(msr.routePath, '/p/marijana-sarolic-robic');
      expect(msr.initials, 'MR');
    });

    test('virtualChannels izostavlja osobe ispod praga', () {
      expect(index.persons.length, 3);
      expect(
        index.virtualChannels.map((p) => p.slug),
        ['marijana-sarolic-robic', 'tomislav-belavic'],
      );
      // Osoba ispod praga i dalje ima profil, samo nije kanal.
      expect(index.bySlug('don-tomislav-lukac')!.isVirtualChannel, isFalse);
    });

    test('prazan / pokvaren odgovor ne baca', () {
      expect(PersonIndex.fromJson(const {}).persons, isEmpty);
      expect(PersonIndex.fromJson(const {}).personCount, 0);
      expect(PersonIndex.fromJson(const {'persons': null}).persons, isEmpty);
      // Zapis bez sluga je neupotrebljiv (nema rutu) → ispada.
      final partial = PersonIndex.fromJson(const {
        'persons': [
          {'name': 'Bez sluga'},
          {'slug': 'ok', 'name': 'OK'},
        ],
      });
      expect(partial.persons.map((p) => p.slug), ['ok']);
      expect(partial.persons.single.isVirtualChannel, isFalse);
      expect(partial.persons.single.durationDisplay, '0h 0m');
      expect(partial.personCount, 1);
      expect(PersonIndex.empty.persons, isEmpty);
    });
  });

  group('PersonHub fixture (§4.2) — kontrolni zbroj MSR', () {
    late PersonHub hub;

    setUp(() => hub = PersonHub.fromJson(_fixture('person_marijana.json')));

    test('17 epizoda, 17 kanala, 49 151 s, točno jedan praćeni kanal', () {
      expect(hub.episodes.length, 17);
      expect(hub.episodeCount, 17);
      expect(hub.episodes.map((e) => e.channel).toSet().length, 17);
      expect(hub.episodes.any((e) => e.channel == '_unlisted'), isFalse);
      expect(
        hub.episodes.fold<int>(0, (s, e) => s + (e.durationSeconds ?? 0)),
        49151,
      );
      expect(hub.totalDurationSeconds, 49151);
      expect(hub.durationDisplay, '13h 39m');
      expect(hub.episodes.where((e) => e.channelTracked).length, 1);
    });

    test('kanal-forma je aktivna, sve epizode su primary', () {
      expect(hub.isVirtualChannel, isTrue);
      expect(hub.primaryEpisodes.length, 17);
      expect(hub.cameoAppearances, isEmpty);
      expect(hub.cameoEpisodeCount, 0);
      expect(hub.firstYear, 2020);
      expect(hub.lastYear, 2026);
      expect(hub.avgMagisteriumScore, 78);
      expect(hub.mentions, isEmpty);
    });

    test('samo praćeni izvorni kanal ima klikabilnu rutu', () {
      final tracked =
          hub.episodes.firstWhere((e) => e.youtubeId == 'dDDwWZPVS0s');
      expect(tracked.channelTracked, isTrue);
      expect(tracked.channelRoutePath, '/c/slijedi-svoj-poziv-2');

      final n1 = hub.episodes.firstWhere((e) => e.youtubeId == 'AVsBPQ7iLSQ');
      expect(n1.channelTracked, isFalse);
      expect(n1.channelRoutePath, isNull);
      expect(n1.channelDisplayName, 'N1');
      expect(n1.channelYoutubeId, 'UCpglal7d5mhV4lA1b3-DsCw');
      // Bez razriješenog first_ts deep-link vodi na cijelu epizodu.
      expect(n1.routePath, '/v/AVsBPQ7iLSQ');
    });

    test('kratak nastup u dugom panelu ostaje primary preko 300 s pravila', () {
      final panel = hub.episodes.firstWhere((e) => e.youtubeId == 'hHyF_UqPKtk');
      expect(panel.speakingSeconds, 980);
      expect(panel.speakingShare! < kPersonPrimaryShareThreshold, isTrue);
      expect(panel.tier, PersonEpisodeTier.primary);

      // Epizoda kojoj F2 nije izmjerio govor također ostaje u glavnom popisu.
      final unmeasured =
          hub.episodes.firstWhere((e) => e.youtubeId == 'PrPHDgVlqIA');
      expect(unmeasured.speakingSeconds, isNull);
      expect(unmeasured.tier, PersonEpisodeTier.primary);
    });
  });

  group('PersonIndexCache', () {
    setUp(personIndexCache.debugReset);
    tearDown(personIndexCache.debugReset);

    test('početno stanje je prazno, ne "nedostupno"', () {
      expect(personIndexCache.loaded, isFalse);
      expect(personIndexCache.unavailable, isFalse);
      expect(personIndexCache.persons, isEmpty);
      expect(personIndexCache.virtualChannels, isEmpty);
      expect(personIndexCache.bySlug('bilo-tko'), isNull);
    });

    test('debugSetIndex puni cache i javlja listenerima', () {
      var notified = 0;
      void listener() => notified++;
      personIndexCache.addListener(listener);
      addTearDown(() => personIndexCache.removeListener(listener));

      personIndexCache
          .debugSetIndex(PersonIndex.fromJson(_fixture('persons_index.json')));

      expect(notified, 1);
      expect(personIndexCache.loaded, isTrue);
      expect(personIndexCache.unavailable, isFalse);
      expect(personIndexCache.virtualChannels.length, 2);
      expect(
        personIndexCache.bySlug('tomislav-belavic')!.name,
        'Tomislav Belavić',
      );
    });

    test('nedostupan indeks (404 na starom backendu) je prazan, ne iznimka',
        () {
      personIndexCache.debugSetIndex(null);
      expect(personIndexCache.unavailable, isTrue);
      expect(personIndexCache.persons, isEmpty);
      expect(personIndexCache.virtualChannels, isEmpty);
    });

    test('loadIndex vraća cache bez mrežnog poziva kad je već učitan', () async {
      final index = PersonIndex.fromJson(_fixture('persons_index.json'));
      personIndexCache.debugSetIndex(index);
      expect(await personIndexCache.loadIndex(), same(index));
    });
  });

  group('PersonChannelFlag', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PersonChannelFlag.instance.debugReset();
    });
    tearDown(PersonChannelFlag.instance.debugReset);

    test('default je OFF', () async {
      await PersonChannelFlag.instance.init();
      expect(PersonChannelFlag.instance.isOn, isFalse);
    });

    test('?vk=1 pali, ?vk=0 gasi, ostalo ne dira spremljeno stanje', () {
      bool? parse(String url) =>
          PersonChannelFlag.overrideFromUri(Uri.parse(url));

      expect(parse('https://domovina.ai/p/x?vk=1'), isTrue);
      expect(parse('https://domovina.ai/p/x?vk=true'), isTrue);
      expect(parse('https://domovina.ai/p/x?vk=ON'), isTrue);
      expect(parse('https://domovina.ai/p/x?vk=0'), isFalse);
      expect(parse('https://domovina.ai/p/x?vk=false'), isFalse);
      expect(parse('https://domovina.ai/p/x'), isNull);
      expect(parse('https://domovina.ai/p/x?vk=maybe'), isNull);
      expect(parse('https://domovina.ai/p/x?a11y=1'), isNull);
      expect(PersonChannelFlag.overrideFromUri(null), isNull);
    });

    test('spremljena vrijednost se dekodira, smeće je OFF', () {
      expect(PersonChannelFlag.decode('1'), isTrue);
      expect(PersonChannelFlag.decode('true'), isTrue);
      expect(PersonChannelFlag.decode('0'), isFalse);
      expect(PersonChannelFlag.decode(null), isFalse);
      expect(PersonChannelFlag.decode('smeće'), isFalse);
    });

    test('setOn perzistira i javlja listenerima', () async {
      var notified = 0;
      void listener() => notified++;
      PersonChannelFlag.instance.addListener(listener);
      addTearDown(() => PersonChannelFlag.instance.removeListener(listener));

      await PersonChannelFlag.instance.setOn(true);
      expect(PersonChannelFlag.instance.isOn, isTrue);
      expect(notified, 1);

      // Isti setter dvaput ne generira lažnu promjenu.
      await PersonChannelFlag.instance.setOn(true);
      expect(notified, 1);

      // Native grana piše u SharedPreferences (na webu bi bio localStorage).
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('person_channel_flag'), '1');

      await PersonChannelFlag.instance.setOn(false);
      expect(PersonChannelFlag.instance.isOn, isFalse);
      expect(notified, 2);
    });

    test('spremljeno stanje se učita pri init()', () async {
      SharedPreferences.setMockInitialValues({'person_channel_flag': '1'});
      PersonChannelFlag.instance.debugReset();
      await PersonChannelFlag.instance.init();
      expect(PersonChannelFlag.instance.isOn, isTrue);
    });
  });
}
