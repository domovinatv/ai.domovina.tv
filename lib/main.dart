import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/episode_screen.dart';
import 'screens/home_screen.dart';
import 'services/update_notifier.dart';

/// App version — prikazuje se u HomeScreen footer.
const String appVersion = '2.0.1';

/// DOMOVINA.ai — prezentacijska Flutter aplikacija za obradjene podcast epizode.
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
      title: 'DOMOVINA.ai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF002F6C), // Croatian navy blue
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF002F6C),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');

        Widget page;

        if (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'v') {
          page = EpisodeScreen(youtubeId: uri.pathSegments[1]);
        } else if (uri.queryParameters['v']?.isNotEmpty == true) {
          page = EpisodeScreen(youtubeId: uri.queryParameters['v']!);
        } else if (uri.pathSegments.length == 2 &&
            uri.pathSegments[0] == 'c') {
          final channelId = uri.pathSegments[1].replaceAll('-', '_');
          page = HomeScreen(initialChannelId: channelId);
        } else if (uri.pathSegments.length == 2 &&
            uri.pathSegments[0] == 'episode') {
          page = EpisodeScreen(youtubeId: uri.pathSegments[1]);
        } else {
          page = const HomeScreen();
        }

        // Instant navigation — no slide/fade animation (forward + reverse)
        return PageRouteBuilder(
          settings: settings,
          pageBuilder: (_, __, ___) => page,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        );
      },
      // home: creates the initial '/' route. onGenerateInitialRoutes ensures
      // it also uses zero-duration transitions (fixes back-navigation jank).
      onGenerateInitialRoutes: (initialRoute) {
        return [
          PageRouteBuilder(
            settings: const RouteSettings(name: '/'),
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        ];
      },
    );
  }
}
