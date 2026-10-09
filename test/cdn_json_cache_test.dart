import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:domovina_ai/services/cdn_json_cache.dart';
import 'package:domovina_ai/services/cdn_store.dart';

/// Ugovor disk cachea (O1 u `docs/2026-10-08-brzina-ucitavanja-naslovnice.md`).
class _MemStore implements CdnStore {
  final Map<String, StoredEntry> data = {};
  bool immutableSupported = true;

  @override
  Future<StoredEntry?> get(StoreBucket b, String url) async =>
      data['${b.name}|$url'];
  @override
  Future<void> put(StoreBucket b, String url, StoredEntry e) async =>
      data['${b.name}|$url'] = e;
  @override
  Future<void> clear() async => data.clear();
  @override
  bool supports(StoreBucket b) =>
      b == StoreBucket.mutable || immutableSupported;
}

const _url = 'https://cdn.domovina.ai/channels/data/hnb.json';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _MemStore store;
  late List<http.Request> requests;

  CdnJsonCache cache(MockClientHandler handler,
          {bool enabled = true, bool conditional = true}) =>
      CdnJsonCache(
        store: store,
        enabled: enabled,
        sendConditionalHeaders: conditional,
        client: MockClient((req) {
          requests.add(req);
          return handler(req);
        }),
      );

  setUp(() {
    store = _MemStore();
    requests = [];
  });

  test('prvi put mreža, spremi s ETag-om', () async {
    final c = cache((_) async =>
        http.Response('v1', 200, headers: {'etag': '"e1"'}));
    expect(await c.getMutable(_url), 'v1');
    await _settle();
    expect(store.data['mutable|$_url']!.etag, '"e1"');
  });

  test('drugi put: spremljeno odmah, revalidacija s If-None-Match, 304 = tiho',
      () async {
    store.data['mutable|$_url'] = const StoredEntry('v1', etag: '"e1"');
    var updates = 0;
    final c = cache((_) async => http.Response('', 304));

    expect(await c.getMutable(_url, onUpdate: (_) => updates++), 'v1');
    await _settle();
    expect(requests.single.headers['If-None-Match'], '"e1"');
    expect(updates, 0);
  });

  test('revalidacija s novim tijelom javlja onUpdate i sprema', () async {
    store.data['mutable|$_url'] = const StoredEntry('v1');
    String? got;
    final c = cache((_) async => http.Response('v2', 200));

    expect(await c.getMutable(_url, onUpdate: (b) => got = b), 'v1');
    await _settle();
    await _settle();
    expect(got, 'v2');
    expect(store.data['mutable|$_url']!.body, 'v2');
  });

  test('web: bez If-None-Match (CORS preflight), isto tijelo = bez update',
      () async {
    store.data['mutable|$_url'] = const StoredEntry('v1', etag: '"e1"');
    var updates = 0;
    final c = cache((_) async => http.Response('v1', 200), conditional: false);

    await c.getMutable(_url, onUpdate: (_) => updates++);
    await _settle();
    expect(requests.single.headers.containsKey('If-None-Match'), isFalse);
    expect(updates, 0);
  });

  test('offline sa spremljenim: vraća spremljeno, ne baca', () async {
    store.data['mutable|$_url'] = const StoredEntry('v1');
    final c = cache((_) async => throw http.ClientException('offline'));
    expect(await c.getMutable(_url), 'v1');
    await _settle();
  });

  test('bez spremljenog i 404: baca kao prije, ništa ne sprema', () async {
    final c = cache((_) async => http.Response('', 404));
    await expectLater(c.getMutable(_url), throwsException);
    expect(store.data, isEmpty);
  });

  test('revalidira se jednom po sesiji', () async {
    store.data['mutable|$_url'] = const StoredEntry('v1');
    final c = cache((_) async => http.Response('', 304));
    await c.getMutable(_url);
    await c.getMutable(_url);
    await _settle();
    expect(requests, hasLength(1));
  });

  test('ugašen (debug / ?nocache=1): uvijek mreža, ništa ne sprema', () async {
    store.data['mutable|$_url'] = const StoredEntry('staro');
    final c = cache((_) async => http.Response('novo', 200), enabled: false);
    expect(await c.getMutable(_url), 'novo');
    expect(store.data['mutable|$_url']!.body, 'staro');
  });

  group('getImmutable', () {
    const u = 'https://cdn.domovina.ai/data/abc/info.json';

    test('drugi put s diska, bez mreže; UTF-8 preživi', () async {
      final c = cache((_) async => throw StateError('ne smije na mrežu'));
      var calls = 0;
      Future<http.Response> fetch() async {
        calls++;
        return http.Response('', 500);
      }

      // Prvi put: pravi UTF-8 bajtovi s mreže.
      Future<http.Response> realFetch() async {
        calls++;
        return http.Response('{"t":"Božje očinstvo"}', 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }

      final first = await c.getImmutable(u, realFetch);
      await _settle();
      final second = await c.getImmutable(u, fetch);
      expect(first.body, '{"t":"Božje očinstvo"}');
      expect(second.body, '{"t":"Božje očinstvo"}');
      expect(calls, 1);
    });

    test('404 se ne sprema', () async {
      final c = cache((_) async => http.Response('', 404));
      final res = await c.getImmutable(u, () async => http.Response('', 404));
      await _settle();
      expect(res.statusCode, 404);
      expect(store.data, isEmpty);
    });

    test('web (immutable nije podržan): uvijek fetch', () async {
      store.immutableSupported = false;
      final c = cache((_) async => http.Response('', 200));
      var calls = 0;
      Future<http.Response> fetch() async {
        calls++;
        return http.Response('{}', 200);
      }

      await c.getImmutable(u, fetch);
      await c.getImmutable(u, fetch);
      expect(calls, 2);
    });
  });
}
