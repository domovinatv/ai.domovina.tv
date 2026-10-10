import 'package:url_launcher/url_launcher.dart';

void openUrlImpl(String url) {
  launchUrl(Uri.parse(url));
}

/// Na nativeu `rel` ne postoji; plaćena poveznica ide u vanjski preglednik.
void openSponsoredUrlImpl(String url) {
  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
