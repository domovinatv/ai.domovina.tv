import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
void _log(String msg) {
  // ignore: avoid_print
  print('[DOMOVINA v$appVersion] $msg');
}

void main() {
  _log('main() start');
  WidgetsFlutterBinding.ensureInitialized();
  _log('WidgetsBinding OK');

  // Path routing — ignoriraj grešku ako je već postavljeno (npr. drugi poziv u testovima)
  try { usePathUrlStrategy(); } catch (_) {}
  _log('usePathUrlStrategy OK');

  // ensureSemantics maknuto — crashao release web build

  _log('MediaKit.ensureInitialized...');
  MediaKit.ensureInitialized();
  _log('MediaKit OK');

  // Uhvati Flutter greške i ispiši u console
  FlutterError.onError = (details) {
    _log('FLUTTER ERROR: ${details.exception}');
    _log('STACK: ${details.stack}');
    FlutterError.presentError(details);
  };

  _log('runApp...');
  runApp(const DominovinaApp());
  _log('runApp OK');
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
    _log('DominovinaApp.build()');
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
      home: const HomeScreen(),
    );
  }
}
