import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/episode_screen.dart';

/// Domovina.ai — prezentacijska Flutter aplikacija za obradjene podcast epizode.
///
/// Promjena epizode: promijeni [kDefaultYoutubeId] ili proslijedi drugi ID
/// u [EpisodeScreen]. Asseti moraju biti na:
///   assets/data/{youtubeId}/*.json
///   assets/images/{youtubeId}/thumbnail.webp
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const DominovinaApp());
}

/// Default video ID za MVP build.
/// Za produkciju: citati iz konfiga, URL parametra, ili route-a.
const String kDefaultYoutubeId = 'H-p2Hl6x7I0';

class DominovinaApp extends StatelessWidget {
  const DominovinaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Domovina.ai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0), // Hrvatska plava
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      // Route za specificni video: /episode/H-p2Hl6x7I0
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');
        if (uri.pathSegments.length == 2 &&
            uri.pathSegments[0] == 'episode') {
          final ytId = uri.pathSegments[1];
          return MaterialPageRoute(
            builder: (_) => EpisodeScreen(youtubeId: ytId),
            settings: settings,
          );
        }
        return MaterialPageRoute(
          builder: (_) => const EpisodeScreen(youtubeId: kDefaultYoutubeId),
          settings: settings,
        );
      },
      home: const EpisodeScreen(youtubeId: kDefaultYoutubeId),
    );
  }
}
