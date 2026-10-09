import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'cdn_store.dart';

/// Cache Storage API iz prozora (bez service workera). Svaka greška —
/// privatni prozor, kvota, blokirana pohrana — znači „nema zapisa", nikad
/// iznimku prema aplikaciji.
CdnStore createStore() => _WebCdnStore();

class _WebCdnStore implements CdnStore {
  /// Verzija u imenu: promjena oblika zapisa = novo ime, stari se obriše u
  /// [clear] ili ostaje neiskorišten.
  static const _name = 'domovina-cdn-v1';

  /// `episode.json` po posjećenoj epizodi — zaseban cache da ga izbacivanje
  /// ([_episodeMax]) ne dira listinge.
  static const _episodeName = 'domovina-episodes-v1';
  static const _episodeMax = 150;
  static const _etagHeader = 'x-domovina-etag';

  Future<web.Cache> _open([StoreBucket bucket = StoreBucket.mutable]) => web
      .window.caches
      .open(bucket == StoreBucket.episode ? _episodeName : _name)
      .toDart;

  @override
  bool supports(StoreBucket bucket) => bucket != StoreBucket.immutable;

  @override
  Future<StoredEntry?> get(StoreBucket bucket, String url) async {
    if (!supports(bucket)) return null;
    try {
      final cache = await _open(bucket);
      final res = await cache.match(url.toJS).toDart;
      if (res == null) return null;
      final body = (await res.text().toDart).toDart;
      return StoredEntry(body, etag: res.headers.get(_etagHeader));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> put(StoreBucket bucket, String url, StoredEntry entry) async {
    if (!supports(bucket)) return;
    try {
      final headers = web.Headers()
        ..append('content-type', 'application/json; charset=utf-8');
      final etag = entry.etag;
      if (etag != null) headers.append(_etagHeader, etag);
      final cache = await _open(bucket);
      await cache
          .put(url.toJS,
              web.Response(entry.body.toJS, web.ResponseInit(headers: headers)))
          .toDart;
      if (bucket == StoreBucket.episode) await _evictEpisodes(cache);
    } catch (_) {}
  }

  /// `keys()` vraća zapise redom upisa (`put` premjesti zapis na kraj), pa
  /// su prvi najdavnije osvježeni.
  Future<void> _evictEpisodes(web.Cache cache) async {
    final keys = (await cache.keys().toDart).toDart;
    for (var i = 0; i < keys.length - _episodeMax; i++) {
      await cache.delete(keys[i]).toDart;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await web.window.caches.delete(_name).toDart;
      await web.window.caches.delete(_episodeName).toDart;
    } catch (_) {}
  }
}
