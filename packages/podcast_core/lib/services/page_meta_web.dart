import 'package:web/web.dart' as web;

/// Default vrijednosti iz web/index.html — snimimo ih pri prvom overrideu
/// da ih resetPageMetaImpl može vratiti bez hardkodiranja.
String? _defaultTitle;
String? _defaultDescription;

void setPageMetaImpl({required String title, String? description}) {
  _defaultTitle ??= web.document.title;
  _defaultDescription ??= _readMeta('name', 'description');

  web.document.title = title;
  _setMeta('property', 'og:title', title);
  _setMeta('name', 'twitter:title', title);
  // og:url prati živu adresnu traku (url_sync je možda već upisao /t/<sec>).
  _setMeta('property', 'og:url', web.window.location.href);
  if (description != null && description.isNotEmpty) {
    _setMeta('name', 'description', description);
    _setMeta('property', 'og:description', description);
    _setMeta('name', 'twitter:description', description);
  }
}

void resetPageMetaImpl() {
  final t = _defaultTitle;
  if (t == null) return; // nikad nije bilo overridea — ništa za vratiti
  web.document.title = t;
  _setMeta('property', 'og:title', t);
  _setMeta('name', 'twitter:title', t);
  _setMeta('property', 'og:url', web.window.location.href);
  final d = _defaultDescription;
  if (d != null && d.isNotEmpty) {
    _setMeta('name', 'description', d);
    _setMeta('property', 'og:description', d);
    _setMeta('name', 'twitter:description', d);
  }
}

String? _readMeta(String attr, String key) =>
    web.document.querySelector('meta[$attr="$key"]')?.getAttribute('content');

void _setMeta(String attr, String key, String value) {
  var el = web.document.querySelector('meta[$attr="$key"]');
  if (el == null) {
    el = web.document.createElement('meta');
    el.setAttribute(attr, key);
    web.document.head?.appendChild(el);
  }
  el.setAttribute('content', value);
}
