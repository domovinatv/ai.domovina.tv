import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/services/data_service.dart';

import 'support/test_brands.dart';

/// Pokreni [body] s lažnim HTTP klijentom koji bilježi tražene putanje i
/// svakome vraća prazan JSON objekt (200).
Future<List<String>> _recordRequests(Future<void> Function() body) async {
  final paths = <String>[];
  await http.runWithClient(body, () {
    return MockClient((req) async {
      paths.add(req.url.path);
      return http.Response('{}', 200);
    });
  });
  return paths;
}

void main() {
  tearDown(() => AppBrand.init(domovinaBrand));

  const svc = DataService(youtubeId: 'abc123');

  /// Svih devet Magisterium dohvata jedne epizode.
  Future<void> loadAllMagisterium() async {
    await svc.loadMagisterium();
    await svc.loadMagisteriumEn();
    await svc.loadMagisteriumBatch();
    await svc.loadMagisteriumBatchEn();
    await svc.loadMagisteriumFull();
    await svc.loadMagisteriumFullPrompt();
    await svc.loadMagisteriumFullV2();
    await svc.loadMagisteriumFullV2En();
    await svc.loadMagisteriumFullV2Prompt();
  }

  test('DOMOVINA (flag upaljen) dohvaća article.magisterium* assete', () async {
    AppBrand.init(domovinaBrand);
    expect(DataService.domainScoreEnabled, isTrue);

    final paths = await _recordRequests(loadAllMagisterium);

    expect(paths.length, 9);
    expect(paths, everyElement(contains('/data/abc123/article.magisterium')));
  });

  test('brend bez domenske ocjene ne šalje nijedan Magisterium zahtjev',
      () async {
    AppBrand.init(brandWithoutDomainScore());
    expect(DataService.domainScoreEnabled, isFalse);

    final paths = await _recordRequests(loadAllMagisterium);

    expect(paths, isEmpty);
    expect(await svc.loadMagisterium(), isNull);
    expect(await svc.loadMagisteriumFullV2(), isNull);
    expect(await svc.loadMagisteriumFullPrompt(), isNull);
  });

  test('ne-Magisterium dohvati nisu zahvaćeni flagom', () async {
    AppBrand.init(brandWithoutDomainScore());

    final paths = await _recordRequests(() async {
      await svc.loadArticle();
    });

    expect(paths, ['/data/abc123/article.json']);
  });
}
