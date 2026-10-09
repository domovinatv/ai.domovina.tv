/// Trajna pohrana CDN odgovora na disku — web: Cache Storage API
/// (`cdn_store_web.dart`), native: datoteke u app support direktoriju
/// (`cdn_store_io.dart`). Koristi je samo [CdnJsonCache].
///
/// Gate je `dart.library.js_interop`, ne `dart.library.html` — `--wasm` build
/// nema `dart:html` pa bi pao na io granu.
library;

import 'cdn_store_io.dart'
    if (dart.library.js_interop) 'cdn_store_web.dart' as platform;

/// Spremljeni odgovor: tijelo, ETag (za uvjetni zahtjev) i kad je spremljen.
class StoredEntry {
  final String body;
  final String? etag;

  const StoredEntry(this.body, {this.etag});
}

/// Vrsta zapisa. [mutable] (listinzi, `index.json`, `home.json`,
/// `search.json`) je mali i ograničen skup, bez izbacivanja. [immutable]
/// (per-epizoda datoteke) raste s brojem otvorenih epizoda pa ima gornju
/// granicu i izbacuje najdavnije korištene. [episode] (`data/<id>/episode.json`)
/// je promjenjiv kao [mutable], ali raste s brojem otvorenih epizoda pa ima
/// gornju granicu kao [immutable].
enum StoreBucket { mutable, immutable, episode }

/// Apstrakcija da testovi mogu podmetnuti memorijsku pohranu.
abstract class CdnStore {
  Future<StoredEntry?> get(StoreBucket bucket, String url);
  Future<void> put(StoreBucket bucket, String url, StoredEntry entry);
  Future<void> clear();

  /// Podržava li platforma [bucket]. Web ne pohranjuje [StoreBucket.immutable]:
  /// per-epizoda datoteke su `immutable` na CDN-u pa ih preglednikov HTTP
  /// cache ionako servira bez mreže (i offline).
  bool supports(StoreBucket bucket);
}

CdnStore createPlatformStore() => platform.createStore();
