import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/episode_screen.dart';
import 'screens/home_screen.dart';

/// Domovina.ai — prezentacijska Flutter aplikacija za obradjene podcast epizode.
///
/// Svi podaci (JSON, slike, video) se loadaju s CDN-a: https://cdn.domovina.ai/
/// Routing:
///   /              - HomeScreen (popis epizoda)
///   /?v=ytId       - EpisodeScreen za dani YouTube ID
///   /episode/ytId  - EpisodeScreen (alternativni format)
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const DominovinaApp());
}

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
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');

        // /?v=<ytId>
        final vtId = uri.queryParameters['v'];
        if (vtId != null && vtId.isNotEmpty) {
          return MaterialPageRoute(
            builder: (_) => EpisodeScreen(youtubeId: vtId),
            settings: settings,
          );
        }

        // /episode/<ytId>
        if (uri.pathSegments.length == 2 &&
            uri.pathSegments[0] == 'episode') {
          return MaterialPageRoute(
            builder: (_) => EpisodeScreen(youtubeId: uri.pathSegments[1]),
            settings: settings,
          );
        }

        // / → HomeScreen
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
      },
      home: const HomeScreen(),
    );
  }
}
