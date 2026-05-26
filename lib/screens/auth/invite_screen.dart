import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../main.dart' show log;

class InviteScreen extends StatefulWidget {
  final String? token;

  const InviteScreen({super.key, this.token});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  bool _processing = true;

  @override
  void initState() {
    super.initState();
    _processInvite();
    AuthService.instance.addListener(_onAuthChange);
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() {
    if (AuthService.instance.isSignedIn) {
      if (mounted) {
        context.go('/');
      }
    }
  }

  Future<void> _processInvite() async {
    // Ako se koristi standardni Supabase magic link za invite, 
    // supabase_flutter će automatski presresti URL i napraviti session.
    // Ovdje čekamo taj event.
    // Ako postoji specifičan token, možemo ga handlati:
    if (widget.token != null) {
      log('Processing invite token: ${widget.token}');
      // TODO: Call backend to verify token if needed.
    }
    
    // Fallback timer in case Supabase event doesn't fire
    await Future.delayed(const Duration(seconds: 3));
    if (mounted && !AuthService.instance.isSignedIn) {
      setState(() {
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prihvati pozivnicu')),
      body: Center(
        child: _processing
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Obrada pozivnice...'),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Došlo je do greške ili je link istekao.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Idi na naslovnicu'),
                  ),
                ],
              ),
      ),
    );
  }
}
