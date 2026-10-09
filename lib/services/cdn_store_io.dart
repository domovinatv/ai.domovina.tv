import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'cdn_store.dart';

/// Datoteke u `<app support>/cdn_cache/<bucket>/`. Ime datoteke je base64url
/// URL-a; ETag u susjednoj `.etag` datoteci. Vrijeme zadnjeg čitanja je
/// `lastModified` datoteke (osvježava se pri čitanju) — po njemu
/// [StoreBucket.immutable] i [StoreBucket.episode] izbacuju najdavnije
/// korištene iznad svoje granice ([_capFor]).
CdnStore createStore() => _IoCdnStore();

class _IoCdnStore implements CdnStore {
  static const _immutableCap = 40 * 1024 * 1024;
  static const _episodeCap = 20 * 1024 * 1024;

  static int? _capFor(StoreBucket bucket) => switch (bucket) {
        StoreBucket.immutable => _immutableCap,
        StoreBucket.episode => _episodeCap,
        StoreBucket.mutable => null,
      };

  Future<Directory?>? _root;

  Future<Directory?> _rootDir() => _root ??= () async {
        try {
          final base = await getApplicationSupportDirectory();
          return Directory('${base.path}/cdn_cache');
        } catch (_) {
          // Testovi i platforme bez path_providera: bez pohrane.
          return null;
        }
      }();

  Future<File?> _file(StoreBucket bucket, String url) async {
    final root = await _rootDir();
    if (root == null) return null;
    final name = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    return File('${root.path}/${bucket.name}/$name');
  }

  @override
  bool supports(StoreBucket bucket) => true;

  @override
  Future<StoredEntry?> get(StoreBucket bucket, String url) async {
    try {
      final f = await _file(bucket, url);
      if (f == null || !await f.exists()) return null;
      final body = await f.readAsString();
      final etagFile = File('${f.path}.etag');
      final etag =
          await etagFile.exists() ? await etagFile.readAsString() : null;
      if (_capFor(bucket) != null) {
        await f.setLastModified(DateTime.now());
      }
      return StoredEntry(body, etag: etag);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> put(StoreBucket bucket, String url, StoredEntry entry) async {
    try {
      final f = await _file(bucket, url);
      if (f == null) return;
      await f.parent.create(recursive: true);
      // Pisanje preko privremene datoteke + rename: prekinut zapis ne smije
      // ostaviti pola JSON-a koji bi se sljedeći put pročitao kao valjan.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(entry.body, flush: true);
      await tmp.rename(f.path);
      final etagFile = File('${f.path}.etag');
      final etag = entry.etag;
      if (etag != null) {
        await etagFile.writeAsString(etag);
      } else if (await etagFile.exists()) {
        await etagFile.delete();
      }
      final cap = _capFor(bucket);
      if (cap != null) await _evict(f.parent, cap);
    } catch (_) {}
  }

  Future<void> _evict(Directory dir, int cap) async {
    final files = <File, FileStat>{};
    var total = 0;
    await for (final e in dir.list()) {
      if (e is! File || e.path.endsWith('.etag') || e.path.endsWith('.tmp')) {
        continue;
      }
      final st = await e.stat();
      files[e] = st;
      total += st.size;
    }
    if (total <= cap) return;
    final oldestFirst = files.entries.toList()
      ..sort((a, b) => a.value.modified.compareTo(b.value.modified));
    for (final e in oldestFirst) {
      if (total <= cap) break;
      total -= e.value.size;
      await e.key.delete();
      final etag = File('${e.key.path}.etag');
      if (await etag.exists()) await etag.delete();
    }
  }

  @override
  Future<void> clear() async {
    try {
      final root = await _rootDir();
      if (root != null && await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (_) {}
  }
}
