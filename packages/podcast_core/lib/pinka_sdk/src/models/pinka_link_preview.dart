library;

/// OG/link preview metapodaci priloženi javnoj poruci donatora (popunjava ih
/// `pinka-webhook` nakon plaćanja; pohranjeni u `contributions.link_preview`).
class PinkaLinkPreview {
  final String url;
  final String? title;
  final String? description;
  final String? image;
  final String? siteName;

  const PinkaLinkPreview({
    required this.url,
    this.title,
    this.description,
    this.image,
    this.siteName,
  });

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
      siteName: (m['siteName'] ?? m['site_name']) as String?,
    );
  }
}
