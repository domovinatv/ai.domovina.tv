import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart' show log;
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
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Prijava u tijeku...'),
          ],
        ),
      ),
    );
  }
}
