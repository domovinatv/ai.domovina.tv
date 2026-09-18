import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/models/channel_index.dart';
import 'package:podcast_core/screens/home/sort_mode.dart';

import 'support/test_brands.dart';

ChannelSummary _channel(String id, {int? avgScore, int videoCount = 1}) =>
    ChannelSummary.fromJson({
      'id': id,
      'name': id,
      'video_count': videoCount,
      'avg_magisterium_score': avgScore,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppBrand.init(domovinaBrand));

  group('ChannelSortMode.offered', () {
    test('DOMOVINA (flag upaljen) nudi i Magisterium sort', () {
      AppBrand.init(domovinaBrand);
      expect(ChannelSortMode.offered, ChannelSortMode.values);
      expect(ChannelSortMode.magisterium.isOffered, isTrue);
    });

    test('brend bez domenske ocjene ne nudi Magisterium sort', () {
      AppBrand.init(brandWithoutDomainScore());
      expect(ChannelSortMode.offered, isNot(contains(ChannelSortMode.magisterium)));
      expect(ChannelSortMode.offered.length, ChannelSortMode.values.length - 1);
      expect(ChannelSortMode.magisterium.isOffered, isFalse);
    });
  });

  group('loadSortMode', () {
    test('spremljeni magisterium s flagom upaljenim ostaje magisterium', () async {
      SharedPreferences.setMockInitialValues({'channel_sort_v1': 'magisterium'});
      AppBrand.init(domovinaBrand);
      expect(await loadSortMode(), ChannelSortMode.magisterium);
    });

    test('spremljeni magisterium s flagom ugašenim pada na zadani mod', () async {
      SharedPreferences.setMockInitialValues({'channel_sort_v1': 'magisterium'});
      AppBrand.init(brandWithoutDomainScore());
      expect(await loadSortMode(), ChannelSortMode.fallback);
      expect(ChannelSortMode.fallback, ChannelSortMode.newest);
    });

    test('nepoznata vrijednost i dalje pada na custom (legacy ponašanje)', () async {
      SharedPreferences.setMockInitialValues({'channel_sort_v1': 'nesto'});
      expect(await loadSortMode(), ChannelSortMode.custom);
    });

    test('bez spremljene vrijednosti vraća null', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await loadSortMode(), isNull);
    });
  });

  group('applySortMode', () {
    final channels = [
      _channel('low', avgScore: 40, videoCount: 3),
      _channel('none', videoCount: 9),
      _channel('high', avgScore: 90, videoCount: 1),
    ];

    test('magisterium s flagom upaljenim sortira po prosjeku, null na kraj', () {
      AppBrand.init(domovinaBrand);
      final ids = applySortMode(channels, ChannelSortMode.magisterium)
          .map((c) => c.id)
          .toList();
      expect(ids, ['high', 'low', 'none']);
    });

    test('magisterium s flagom ugašenim se ponaša kao zadani mod', () {
      AppBrand.init(brandWithoutDomainScore());
      final got = applySortMode(channels, ChannelSortMode.magisterium)
          .map((c) => c.id)
          .toList();
      final expected = applySortMode(channels, ChannelSortMode.fallback)
          .map((c) => c.id)
          .toList();
      expect(got, expected);
    });
  });
}
