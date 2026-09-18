import 'package:podcast_core/podcast_core.dart';

/// Ulazna točka DOMOVINA.ai ljuske. Sav kod aplikacije je u paketu
/// `packages/podcast_core`; ljuska samo kaže KOJI brend pokreće. Drugi brend
/// (Podcasterium) je druga ljuska s drugim `BrandConfig`-om nad istim paketom.
Future<void> main() => runPodcastApp(domovinaBrand);
