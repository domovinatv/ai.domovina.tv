import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'l10n/app_localizations.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'services/background_audio.dart';
import 'services/entitlement_service.dart';
import 'services/locale_service.dart';
import 'services/revenue_cat_service.dart';
import 'services/theme_mode_service.dart';
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
const String appVersion = '2.0.86';

/// Console logger s verzijom — koristi za debug u release web buildovima
/// gdje su stack traceovi minificirani. Vidi CLAUDE.md za detalje.
// ignore: avoid_print
void log(String msg) => print('[DOMOVINA v$appVersion] $msg');

void main() async {
  log('main() start');
  WidgetsFlutterBinding.ensureInitialized();

  try { usePathUrlStrategy(); } catch (_) {}

  // Gasi browserov native right-click menu na webu da bi se vidjeli NAŠI custom
  // context menu-i (npr. "Kopiraj poveznicu" na karticama kanala/epizoda —
  // ShareContextMenu). Bez ovoga Flutter web pušta browserov menu koji zasjeni
  // showMenu(). App-wide je (nema per-element API-ja u frameworku).
  if (kIsWeb) {
    try { await BrowserContextMenu.disableContextMenu(); } catch (_) {}
  }

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
    // Ako URL nosi auth parametre (povratak s magic link / OAuth redirecta),
    // NE prijavljuj anonimno — inače anon sesija pregazi/utrkuje stvarnu sesiju
    // koja stiže iz URL-a → /auth/callback zaglavi na "Prijava u tijeku".
    final hasAuthCallback = kIsWeb &&
        (Uri.base.fragment.contains('access_token') ||
            Uri.base.queryParameters.containsKey('code') ||
            Uri.base.path.contains('/auth/callback') ||
            Uri.base.path.contains('/login-callback'));
    if (client.auth.currentUser == null && !hasAuthCallback) {
      try {
        await client.auth.signInAnonymously();
        log('Supabase: signed in anonymously');
      } catch (e) {
        log('Supabase: anonymous sign-in failed — $e');
      }
    } else if (hasAuthCallback) {
      log('Supabase: auth callback URL detektiran — preskačem anon sign-in');
    } else {
      log('Supabase: restored session for ${client.auth.currentUser?.id}');
    }
  } else {
    log('Supabase: SUPABASE_URL / SUPABASE_ANON_KEY not set; running offline');
  }

  // RevenueCat mora biti konfiguriran PRIJE AuthService.init() jer init odmah
  // resolva trenutnog usera pa Purchases.logIn(uid) treba configured SDK.
  // No-op na webu/TV-u (SDK bypassan) — vidi revenue_cat_service.dart.
  await RevenueCatService.instance.configure();

  await AuthService.instance.init();
  // Entitlement state (domovina_plus) — čita Supabase red na svim platformama
  // + folda mobilni optimistic SDK unlock. Mora poslije AuthService.init().
  await EntitlementService.instance.init();
  await WatchProgressService.instance.init();
  // Ucitaj spremljenu temu (default tamna za nove korisnike).
  await ThemeController.instance.init();
  // Ucitaj spremljeni UI jezik (default hrvatski).
  await LocaleController.instance.init();

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

/// Globalni ScaffoldMessenger key — omogućuje prikaz SnackBar-a iz servisa
/// (npr. AuthService) neovisno o BuildContext-u koji je možda već unmountan
/// (npr. nakon zatvaranja bottom sheeta). Vezan na MaterialApp ispod.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class _DominovinaAppState extends State<DominovinaApp> {
  final _messengerKey = rootScaffoldMessengerKey;
  late final _router = createRouter();

  @override
  void initState() {
    super.initState();
    listenForAppUpdate(_showUpdateSnackBar);
  }

  void _showUpdateSnackBar() {
    final ctx = _messengerKey.currentContext;
    final l = ctx != null ? AppLocalizations.of(ctx) : null;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(l?.updateAvailable ?? 'Dostupna je nova verzija'),
        duration: const Duration(days: 1),
        action: SnackBarAction(
          label: l?.updateRefresh ?? 'Osvježi',
          onPressed: reloadPage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Na Android TV-u forsiramo dark TV temu (10-foot UI uvijek tamno).
    // Mobile/desktop/web prate korisnikov odabir iz ThemeController-a
    // (default tamna za nove korisnike, prebacivo preko ikone u home baru).
    final isTv = TvMode.isTv;
    if (isTv) {
      return MaterialApp.router(
        scaffoldMessengerKey: _messengerKey,
        title: 'DOMOVINA.ai',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.tv(),
        darkTheme: AppTheme.tv(),
        themeMode: ThemeMode.dark,
        // TV je hrvatsko tržište (10-foot UI) — fiksno hrvatski.
        locale: const Locale('hr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _router,
      );
    }
    return AnimatedBuilder(
      // Rebuild na promjenu teme ILI UI jezika.
      animation: Listenable.merge(
        [ThemeController.instance, LocaleController.instance],
      ),
      builder: (context, _) => MaterialApp.router(
        scaffoldMessengerKey: _messengerKey,
        title: 'DOMOVINA.ai',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeController.instance.mode,
        locale: LocaleController.instance.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _router,
      ),
    );
  }
}
