import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart' show log;
import '../../onboarding/ui/auth_ui.dart';
import '../../services/auth_service.dart';

class AuthCallbackScreen extends StatefulWidget {
  const AuthCallbackScreen({super.key});

  @override
  State<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<AuthCallbackScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChange);
    // Navigacija MORA biti izvan initState/builda. Ako je sesija već
    // uspostavljena tijekom Supabase.initialize (čest slučaj na webu nakon
    // OAuth redirecta), context.go() pozvan sinkrono u initState se tiho
    // izgubi jer router još nije spreman → ekran zaglavi na "Prijava u tijeku".
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() => _checkSession();

  void _checkSession() {
    if (_navigated || !mounted) return;
    if (AuthService.instance.isSignedIn) {
      _navigated = true;
      log('AuthCallback: signed in → redirect /');
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DomovinaLogoMark(size: 72),
            const SizedBox(height: 18),
            const DomovinaWordmark(fontSize: 22),
            const SizedBox(height: 14),
            const TricolorAccent(width: 52),
            const SizedBox(height: 32),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Prijava u tijeku…',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
