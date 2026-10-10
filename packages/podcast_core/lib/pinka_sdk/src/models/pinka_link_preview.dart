library;

/// OG/link preview metapodaci priloženi javnoj poruci donatora (popunjava ih
/// `pinka-webhook` nakon plaćanja; pohranjeni u `contributions.link_preview`).
class PinkaLinkPreview {
  final String url;
  final String? title;
  final String? description;
  /// `og:image` s TUĐEG hosta — samo podatak, NIKAD se ne crta: `Image.network`
  /// na njega odao bi IP svakog posjetitelja zida vlasniku tog hosta.
  final String? image;

  /// Kopija slike u našem storageu (`pinka-og-cache`, Supabase → R2), koju
  /// `pinka-webhook` napravi jednom po doprinosu. Jedina slika koju zid crta.
  final String? imageCached;

  /// Dimenzije keširane slike (iz zaglavlja, pri keširanju). Zid po njima
  /// bira raspored PRIJE učitavanja: OG „standard" je 1200×630, ali stvarne
  /// slike su i 2,7 : 1 i portretne (izmjereno 28.9.2026.).
  final int? imageWidth;
  final int? imageHeight;
  final String? siteName;

  const PinkaLinkPreview({
    required this.url,
    this.title,
    this.description,
    this.image,
    this.imageCached,
    this.imageWidth,
    this.imageHeight,
    this.siteName,
  });

  /// širina / visina, ili null kad dimenzije nisu poznate.
  double? get imageAspect {
    final w = imageWidth, h = imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  bool get hasContent =>
      (title?.isNotEmpty ?? false) || (description?.isNotEmpty ?? false);

  /// Tolerantan parser — `link_preview` je jsonb pa stiže kao Map ili null.
  static PinkaLinkPreview? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final url = m['url'] as String?;
    if (url == null || url.isEmpty) return null;
    return PinkaLinkPreview(
      url: url,
      title: m['title'] as String?,
      description: m['description'] as String?,
      image: m['image'] as String?,
      imageCached: _ownImageUrl(m['image_cached']),
      imageWidth: (m['image_width'] as num?)?.toInt(),
      imageHeight: (m['image_height'] as num?)?.toInt(),
      siteName: (m['siteName'] ?? m['site_name']) as String?,
    );
  }
}

/// Hostovi na kojima živi NAŠA kopija slike. Sve ostalo se odbacuje — i kad bi
/// `image_cached` greškom nosio tuđi URL, zid ga ne smije dohvatiti.
const _ownImageHosts = {'api.domovina.ai'};

String? _ownImageUrl(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final u = Uri.tryParse(raw);
  if (u == null || u.scheme != 'https' || !_ownImageHosts.contains(u.host)) {
    return null;
  }
  return raw;
}
