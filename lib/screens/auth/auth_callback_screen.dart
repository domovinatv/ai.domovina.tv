import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';

class AuthCallbackScreen extends StatefulWidget {
  const AuthCallbackScreen({super.key});

  @override
  State<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<AuthCallbackScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
    AuthService.instance.addListener(_onAuthChange);
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() {
    _checkSession();
  }

  void _checkSession() {
    if (AuthService.instance.isSignedIn) {
      if (mounted) {
        context.go('/');
      }
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
