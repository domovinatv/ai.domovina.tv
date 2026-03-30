import 'package:url_launcher/url_launcher.dart';

void openUrlImpl(String url) {
  launchUrl(Uri.parse(url));
}
