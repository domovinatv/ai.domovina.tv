import 'package:podcast_core/podcast_core.dart';

import 'certilia/certilia_auth_plugin.dart';

/// Ulazna točka DOMOVINA.ai ljuske. Sav kod aplikacije je u paketu
/// `packages/podcast_core`; ljuska kaže KOJI brend pokreće i koje
/// DOMOVINA-specifične plugine donosi (e-Osobna). Drugi brend (Podcasterium)
/// je druga ljuska s drugim `BrandConfig`-om nad istim paketom.
Future<void> main() => runPodcastApp(
      domovinaBrand,
      authPlugins: const [CertiliaAuthPlugin()],
    );
