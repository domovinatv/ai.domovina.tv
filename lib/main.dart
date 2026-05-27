import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'services/background_audio.dart';
import 'services/tv_mode.dart';
import 'services/update_notifier.dart';
import 'services/watch_progress_service.dart';
import 'theme/app_theme.dart';

/// Supabase backend (self-hosted na Coolify, Kong gateway).
/// Konfiguracija dolazi preko --dart-define u build/run komandi; vidi
/// .env za lokalni dev i scripts/deploy.sh za production propagation.
const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// App version — prikazuje se u HomeScreen footer.
const String appVersion = '2.0.12';

/// Console logger s verzijom — koristi za debug u release web buildovima
/// gdje su stack traceovi minificirani. Vidi CLAUDE.md za detalje.
// ignore: avoid_print
void log(String msg) => print('[DOMOVINA v$appVersion] $msg');

void main() async {
  log('main() start');
  WidgetsFlutterBinding.ensureInitialized();

  try { usePathUrlStrategy(); } catch (_) {}

  // ensureSemantics ZABRANJENO na webu — crasha release build.
  // Vidi CLAUDE.md "Known Issues".

  // TV detekcija mora biti prije runApp jer router i theme citaju TvMode.isTv
  // sinkrono. Override: --dart-define=FORCE_TV=true za desktop iteraciju.
  await TvMode.init();

  MediaKit.ensureInitialized();
  await BackgroundAudio.init();

  // Supabase init MORA biti prije AuthService.init() — auth service sluša
  // Supabase auth state changes. Bez konfiguracije app radi u offline mode
  // (mock fallback ostaje, ali pravi backend pozivi su no-op).
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
      debug: false,
    );
    // Anonymous sign-in ako nema postojeće sesije. Trigger backend-side
    // (on_auth_user_created) automatski kreira profile red.
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      try {
        await client.auth.signInAnonymously();
        log('Supabase: signed in anonymously');
      } catch (e) {
        log('Supabase: anonymous sign-in failed — $e');
      }
    } else {
      log('Supabase: restored session for ${client.auth.currentUser?.id}');
    }
  } else {
    log('Supabase: SUPABASE_URL / SUPABASE_ANON_KEY not set; running offline');
  }

  await AuthService.instance.init();
  await WatchProgressService.instance.init();

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
    // Na Android TV-u forsiramo dark TV temu (10-foot UI uvijek tamno);
    // mobile/desktop/web prate system theme mode kao i prije.
    final isTv = TvMode.isTv;
    return MaterialApp.router(
      scaffoldMessengerKey: _messengerKey,
      title: 'DOMOVINA.ai',
      debugShowCheckedModeBanner: false,
      theme: isTv ? AppTheme.tv() : AppTheme.light(),
      darkTheme: isTv ? AppTheme.tv() : AppTheme.dark(),
      themeMode: isTv ? ThemeMode.dark : ThemeMode.system,
      routerConfig: _router,
    );
  }
}
