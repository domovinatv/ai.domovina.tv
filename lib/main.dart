import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:media_kit/media_kit.dart';
import 'router/app_router.dart';
import 'services/update_notifier.dart';

/// App version — prikazuje se u HomeScreen footer.
const String appVersion = '2.0.1';

/// Console logger s verzijom — koristi za debug u release web buildovima
/// gdje su stack traceovi minificirani. Vidi CLAUDE.md za detalje.
// ignore: avoid_print
void log(String msg) => print('[DOMOVINA v$appVersion] $msg');

void main() {
  log('main() start');
  WidgetsFlutterBinding.ensureInitialized();

  try { usePathUrlStrategy(); } catch (_) {}

  // ensureSemantics ZABRANJENO na webu — crasha release build.
  // Vidi CLAUDE.md "Known Issues".

  MediaKit.ensureInitialized();

  // Uhvati Flutter greske i ispisi u console (vidljivo i u minified buildu)
  FlutterError.onError = (details) {
    log('FLUTTER ERROR: ${details.exception}');
    log('STACK: ${details.stack}');
    FlutterError.presentError(details);
  };

  log('runApp');
  runApp(const DominovinaApp());
}

class DominovinaApp extends StatefulWidget {
  const DominovinaApp({super.key});

  @override
  State<DominovinaApp> createState() => _DominovinaAppState();
}

class _DominovinaAppState extends State<DominovinaApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final _router = createRouter();

  @override
  void initState() {
    super.initState();
    listenForAppUpdate(_showUpdateSnackBar);
  }

  void _showUpdateSnackBar() {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text('Nova verzija je dostupna'),
        duration: const Duration(days: 1),
        action: SnackBarAction(
          label: 'OSVJEZI',
          onPressed: reloadPage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
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
      routerConfig: _router,
    );
  }
}
