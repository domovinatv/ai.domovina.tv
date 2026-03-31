import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/episode_screen.dart';
import 'screens/home_screen.dart';
import 'services/update_notifier.dart';

/// App version — prikazuje se u HomeScreen footer.
const String appVersion = '1.1.3';

/// Domovina.ai — prezentacijska Flutter aplikacija za obradjene podcast epizode.
///
/// Svi podaci (JSON, slike, video) se loadaju s CDN-a: https://cdn.domovina.ai/
/// Routing:
///   /              - HomeScreen (unos YouTube ID-a)
///   /v/ytId        - EpisodeScreen — permalink format za sharing
///   /?v=ytId       - EpisodeScreen — query param format
///   /episode/ytId  - EpisodeScreen — legacy format
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Path routing — ignoriraj grešku ako je već postavljeno (npr. drugi poziv u testovima)
  try { usePathUrlStrategy(); } catch (_) {}

  // Semantics (flt-semantics DOM overlay) — uvijek uključeno u release buildu.
  // U debug/test modu test framework upravlja semanticsima sam.
  if (kReleaseMode) {
    SemanticsBinding.instance.ensureSemantics();
    // Handle namjerno nije pohranjen — u release modu app živi zauvijek,
    // handle ne treba biti disposean.
  }

  MediaKit.ensureInitialized();
  runApp(const DominovinaApp());
}

class DominovinaApp extends StatefulWidget {
  const DominovinaApp({super.key});

  @override
  State<DominovinaApp> createState() => _DominovinaAppState();
}

class _DominovinaAppState extends State<DominovinaApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    listenForAppUpdate(_showUpdateSnackBar);
  }

  void _showUpdateSnackBar() {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text('Nova verzija je dostupna'),
        duration: const Duration(days: 1), // persist until action
        action: SnackBarAction(
          label: 'OSVJEZI',
          onPressed: reloadPage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
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

        // /v/<ytId> — permalink za sharing
        if (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'v') {
          return MaterialPageRoute(
            builder: (_) => EpisodeScreen(youtubeId: uri.pathSegments[1]),
            settings: settings,
          );
        }

        // /?v=<ytId>
        final vtId = uri.queryParameters['v'];
        if (vtId != null && vtId.isNotEmpty) {
          return MaterialPageRoute(
            builder: (_) => EpisodeScreen(youtubeId: vtId),
            settings: settings,
          );
        }

        // /episode/<ytId> — legacy
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
