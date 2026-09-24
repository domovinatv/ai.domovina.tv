/// Dijeljeni korpus nosi `magisterium_score` u JSON-u kanala i osoba; brend
/// bez domenske ocjene ne smije je vidjeti ni na jednom ekranu (izmjereno
/// 24.9.2026: Podcasterium je na /c/domovina-tv prikazivao bedž s crkvom).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/models/channel_detail.dart';

import 'support/test_brands.dart';

void main() {
  const json = {
    'youtube_id': 'MGLq9v3AtvE',
    'title': 't',
    'magisterium_score': 90,
  };

  tearDown(() => AppBrand.init(domovinaBrand));

  test('DOMOVINA čita ocjenu', () {
    AppBrand.init(domovinaBrand);
    expect(ChannelVideo.fromJson(json).magisteriumScore, 90);
  });

  test('brend bez domenske ocjene dobiva null', () {
    AppBrand.init(brandWithoutDomainScore());
    expect(ChannelVideo.fromJson(json).magisteriumScore, isNull);
  });
}
