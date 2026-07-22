/// Ekran na koji se vraća OAuth / magic link redirect (/auth/callback i
/// /login-callback). Čeka da sesija stigne kroz onAuthStateChange pa
/// redirecta na početnu.
///
/// Failure path: GoTrue na neuspjeh appenda error parametre na redirect URL
/// (query ILI fragment, ovisno o flowu) — parsiramo ih i odmah pokažemo
/// grešku. Ako ni sesija ni greška ne stignu unutar [_timeout], prestajemo
/// se vrtjeti i nudimo retry — spinner nikad ne smije biti beskonačan.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart' show log, rootScaffoldMessengerKey;
import '../../onboarding/ui/auth_sheet.dart';
import '../../onboarding/ui/auth_ui.dart';
import '../../services/auth_return_path.dart';
import '../../services/auth_service.dart';
import '../../services/local_prefs.dart';
import '../../services/locale_service.dart';

class AuthCallbackScreen extends StatefulWidget {
  const AuthCallbackScreen({super.key});

  @override
  State<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<AuthCallbackScreen> {
  static const _timeout = Duration(seconds: 12);

  bool _navigated = false;
  String? _error;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChange);

    final urlError = kIsWeb ? _errorFromUrl() : null;
    if (urlError != null) {
      _error = urlError;
    } else {
      _timeoutTimer = Timer(_timeout, _onTimeout);
    }

    // Navigacija MORA biti izvan initState/builda. Ako je sesija već
    // uspostavljena tijekom Supabase.initialize (čest slučaj na webu nakon
    // OAuth redirecta), context.go() pozvan sinkrono u initState se tiho
    // izgubi jer router još nije spreman → ekran zaglavi na "Prijava u tijeku".
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    AuthService.instance.removeListener(_onAuthChange);
    super.dispose();
  }

  /// GoTrue error parametri mogu biti u query stringu (PKCE) ili u
  /// fragmentu (implicit flow): error, error_code, error_description.
  String? _errorFromUrl() {
    final query = Uri.base.queryParameters;
    Map<String, String> fragment = const {};
    try {
      fragment = Uri.splitQueryString(Uri.base.fragment);
    } catch (_) {
      // Fragment nije query-encoded (npr. ruta) — ignoriraj.
    }
    final error = query['error'] ?? fragment['error'];
    if (error == null) return null;

    final code = query['error_code'] ?? fragment['error_code'];
    final description =
        query['error_description'] ?? fragment['error_description'];
    log('AuthCallback: URL error=$error code=$code desc=$description');

    return switch (code) {
      'otp_expired' => appStrings.authErrLinkExpired,
      'user_banned' => appStrings.authErrUserBanned,
      'signup_disabled' => appStrings.authErrSignupDisabled,
      _ => switch (error) {
          'access_denied' => appStrings.authErrAccessDenied,
          'server_error' => appStrings.authErrServerError,
          _ => appStrings.authErrGeneric,
        },
    };
  }

  void _onTimeout() {
    if (_navigated || !mounted) return;
    log('AuthCallback: timeout — session never arrived');
    setState(() {
      _error = appStrings.authErrTimeout;
    });
  }

  void _onAuthChange() => _checkSession();

  void _checkSession() {
    if (_navigated || !mounted) return;
    if (AuthService.instance.isSignedIn) {
      _navigated = true;
      _timeoutTimer?.cancel();
      final user = AuthService.instance.currentUser;
      if (user?.provider != null) {
        setLocalStorageString(lastProviderKey, user!.provider!.name);
      }
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(appStrings.authSignedInAs(
              user?.displayName ?? user?.email ?? appStrings.authUserFallback)),
        ),
      );
      context.go(_returnDestination());
    }
  }

  /// Ruta na koju se vraćamo nakon prijave — ona s koje je login krenuo
  /// (spremljena u [authReturnToKey] prije OAuth redirecta), inače '/'.
  /// Validacija (open-redirect guard) u auth_return_path.dart (unit-testirano).
  String _returnDestination() {
    final saved = getLocalStorageString(authReturnToKey);
    setLocalStorageString(authReturnToKey, '');
    final dest = sanitizeReturnPath(saved);
    log('AuthCallback: signed in → redirect $dest');
    return dest;
  }

  void _retry() {
    // Sheet preko ovog ekrana: auth listener ostaje aktivan pa uspješna
    // prijava iz sheeta automatski redirecta na / kroz _checkSession.
    setState(() => _error = null);
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_timeout, _onTimeout);
    showAuthSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const DomovinaLogoMark(size: 72),
                const SizedBox(height: 18),
                const DomovinaWordmark(fontSize: 22),
                const SizedBox(height: 14),
                const TricolorAccent(width: 52),
                const SizedBox(height: 32),
                if (_error == null) ...[
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation(theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    l.authSigningIn,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  Icon(Icons.error_outline,
                      size: 40, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(height: 1.35),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l.commonRetry),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: Text(
                      l.commonGoHome,
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
