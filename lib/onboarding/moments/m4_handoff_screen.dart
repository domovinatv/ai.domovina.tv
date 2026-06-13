/// M4 — Cross-device handoff screen na /handoff i /handoff/:code.
/// - "Pošalji" tab: trenutni (logged-in) user generira 6-znamenkasti kod, dijeli.
/// - "Primi" tab: drugi uređaj unosi kod, dobije isti račun.
///
/// Pravi backend swap koristi RPC create/consume_handoff_token (vidi
/// docs/backend-prompts/06-handoff-rpc.md).
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/handoff_service.dart';
import '../ui/auth_sheet.dart';


class HandoffScreen extends StatefulWidget {
  final String? prefilledCode;
  const HandoffScreen({super.key, this.prefilledCode});

  @override
  State<HandoffScreen> createState() => _HandoffScreenState();
}

class _HandoffScreenState extends State<HandoffScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.prefilledCode != null ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Prebaci na drugi uređaj'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          indicatorColor: theme.colorScheme.tertiary,
          tabs: const [
            Tab(icon: Icon(Icons.upload), text: 'Pošalji'),
            Tab(icon: Icon(Icons.download), text: 'Primi'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const _SendTab(),
          _ReceiveTab(prefilledCode: widget.prefilledCode),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SEND tab — generiraj kod
// ---------------------------------------------------------------------------

class _SendTab extends StatefulWidget {
  const _SendTab();

  @override
  State<_SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<_SendTab> {
  String? _code;
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = AuthService.instance;

    if (auth.isAnonymous) {
      return _NotSignedInPrompt(
        title: 'Prvo se prijavi',
        subtitle:
            'Da bi prebacio cijeli svoj napredak na drugi uređaj, prvo se prijavi na ovom — onda i drugi uređaj može pristupiti istom računu.',
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Icon(Icons.devices_other, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Pošalji prijavu na drugi uređaj',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Otvori DOMOVINA.ai/handoff na drugom uređaju i unesi kod ispod. Kod vrijedi 5 minuta.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_code == null) ...[
              FilledButton.icon(
                onPressed: _loading ? null : _generate,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bolt),
                label: const Text('Generiraj kod'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.croBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                ),
              ),
            ] else ...[
              _CodeDisplay(code: _code!),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copy(_code!),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Kopiraj'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _code = null;
                    }),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Novi kod'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Vrijedi 5 minuta',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final handoff = await HandoffService.instance.createCode();
      if (!mounted) return;
      setState(() {
        _code = handoff.code;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Greška: $e';
        _loading = false;
      });
    }
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kod kopiran u clipboard')),
    );
  }
}

class _CodeDisplay extends StatelessWidget {
  final String code;
  const _CodeDisplay({required this.code});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pretty = '${code.substring(0, 3)}-${code.substring(3)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.primaryContainer,
        border: Border.all(color: theme.colorScheme.primary, width: 2),
      ),
      child: Text(
        pretty,
        style: theme.textTheme.displayMedium?.copyWith(
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onPrimaryContainer,
          letterSpacing: 8,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// RECEIVE tab — unesi kod
// ---------------------------------------------------------------------------

class _ReceiveTab extends StatefulWidget {
  final String? prefilledCode;
  const _ReceiveTab({this.prefilledCode});

  @override
  State<_ReceiveTab> createState() => _ReceiveTabState();
}

class _ReceiveTabState extends State<_ReceiveTab> {
  late final TextEditingController _ctrl;
  bool _loading = false;
  String? _error;

  /// True nakon što je action_link otvoren; sesija stiže asinkrono preko
  /// AuthService listenera (mobile/TV). Na webu stranica navigira pa se ovaj
  /// state ni ne prikaže.
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.prefilledCode ?? '');
    AuthService.instance.addListener(_onAuthChange);
    if (widget.prefilledCode != null && widget.prefilledCode!.length == 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
    }
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChange);
    _ctrl.dispose();
    super.dispose();
  }

  void _onAuthChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_opening && AuthService.instance.isSignedIn) {
      return const _ConsumedSuccess();
    }
    if (_opening) {
      return const _OpeningSignIn();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(Icons.phone_iphone, size: 56, color: theme.colorScheme.tertiary),
            const SizedBox(height: 16),
            Text(
              'Imaš kod s drugog uređaja?',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Unesi 6-znamenkasti kod koji si dobio na drugom uređaju da preuzmeš njegov račun ovdje.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _ctrl,
              autofocus: widget.prefilledCode == null,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: const InputDecoration(
                hintText: '000000',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.tertiary,
                foregroundColor: theme.colorScheme.onTertiary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Preuzmi prijavu'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Kod mora imati 6 znamenki');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Otvara magic action_link: web navigira u istom tabu (app se reloada
      // signed-in), mobile/TV otvara vanjski browser → deep link vraća sesiju.
      // Stvarni sign-in stiže preko onAuthStateChange → AuthService listener.
      await HandoffService.instance.consumeCode(code);

      if (!mounted) return;
      setState(() {
        _opening = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is StateError || e is FormatException
            ? e.toString().replaceFirst(RegExp(r'^[^:]*: '), '')
            : 'Greška: $e';
        _loading = false;
      });
    }
  }
}

class _OpeningSignIn extends StatelessWidget {
  const _OpeningSignIn();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Otvaram prijavu…',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ako se otvori preglednik, potvrdi prijavu pa se vrati u aplikaciju.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsumedSuccess extends StatelessWidget {
  const _ConsumedSuccess();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = AuthService.instance.currentUser;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 72, color: Colors.green.shade600),
            const SizedBox(height: 24),
            Text(
              'Uspješno!',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Prijavljen kao ${user?.displayName ?? "korisnik"}.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (user?.email != null) ...[
              const SizedBox(height: 4),
              Text(
                user!.email!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.croBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Idi na početnu'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotSignedInPrompt extends StatelessWidget {
  final String title;
  final String subtitle;
  const _NotSignedInPrompt({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Prijavi se'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.croBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
              ),
              // NE origin: handoff — njegov subtitle ("Kod je verificiran…")
              // vrijedi samo za receive flow; ovdje šaljemo vlastiti copy.
              onPressed: () => showAuthSheet(
                context,
                headlineOverride: 'Prijavi se',
                subtitleOverride:
                    'Za slanje prijave na drugi uređaj prvo se prijavi na ovom.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
