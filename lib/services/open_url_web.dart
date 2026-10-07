import 'package:web/web.dart' as web;

void openUrlImpl(String url) {
  web.window.open(url, '_blank');
}

/// Plaćena poveznica: otvara se kroz pravi `<a rel="sponsored">`, a ne kroz
/// `window.open`, da oznaka plaćenog linka putuje s navigacijom (Google
/// smjernice za plaćene linkove). `noopener` jer je odredište tuđe.
void openSponsoredUrlImpl(String url) {
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..target = '_blank'
    ..rel = 'sponsored noopener noreferrer';
  web.document.body?.append(a);
  a.click();
  a.remove();
}
