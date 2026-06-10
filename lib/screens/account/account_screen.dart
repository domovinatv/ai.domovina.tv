/// Moj račun — account management ekran (/account).
///
/// Sekcije: profil (ime/e-mail/KYC), povezane prijavne metode, passkeyji
/// (lista + uklanjanje + dodavanje), uređaji (handoff), odjava s potvrdom,
/// te opasna zona s trajnim brisanjem računa (App Store Guideline 5.1.1(v) —
/// app koji nudi kreiranje računa MORA nuditi i brisanje u appu).
///
/// Passkey list/delete i account-delete backend grane su specificirane u
/// docs/backend-prompts/10-account-management.md; dok ne postoje, UI
/// degradira graceful (PasskeyFailure.unsupported / 404 poruke).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart' show log, rootScaffoldMessengerKey;
import '../../onboarding/ui/auth_sheet.dart';
import '../../services/auth_service.dart';
import '../../services/passkey_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  List<PasskeyInfo>? _passkeys;
  bool _passkeysLoading = true;
  bool _passkeysUnsupported = false;
  String? _passkeysError;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChange);
    _loadPasskeys();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPasskeys() async {
    if (!AuthService.instance.isSignedIn) {
      setState(() => _passkeysLoading = false);
      return;
    }
    setState(() {
      _passkeysLoading = true;
      _passkeysError = null;
    });
    try {
      final list = await PasskeyService.instance.listPasskeys();
      if (!mounted) return;
      setState(() {
        _passkeys = list;
        _passkeysLoading = false;
      });
    } on PasskeyFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _passkeysLoading = false;
        _passkeysUnsupported = e.unsupported;
        _passkeysError = e.unsupported ? null : e.message;
      });
    } catch (e) {
      log('AccountScreen._loadPasskeys: $e');
      if (!mounted) return;
      setState(() {
        _passkeysLoading = false;
        _passkeysError = 'Dohvat passkeyja nije uspio.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = AuthService.instance;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Moj račun'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: auth.isSignedIn ? _signedInBody(theme) : _anonymousBody(theme),
    );
  }

  // ── anonymous state ──────────────────────────────────────────────────────

  Widget _anonymousBody(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_outline,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Nisi prijavljen',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Prijavi se da upravljaš svojim računom, passkeyjima i podacima.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Prijavi se'),
                onPressed: () => showAuthSheet(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── signed-in state ──────────────────────────────────────────────────────

  Widget _signedInBody(ThemeData theme) {
    final user = AuthService.instance.currentUser!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _profileCard(theme, user),
              const SizedBox(height: 16),
              _sectionLabel(theme, 'PRIJAVNE METODE'),
              _identitiesCard(theme),
              const SizedBox(height: 16),
              _sectionLabel(theme, 'PASSKEYJI'),
              _passkeysCard(theme),
              const SizedBox(height: 16),
              _sectionLabel(theme, 'UREĐAJI'),
              _devicesCard(theme),
              const SizedBox(height: 16),
              _signOutCard(theme),
              const SizedBox(height: 24),
              _sectionLabel(theme, 'OPASNA ZONA', color: theme.colorScheme.error),
              _dangerCard(theme),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color ?? theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _card(ThemeData theme, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: child,
    );
  }

  Widget _profileCard(ThemeData theme, AppUser user) {
    final cs = theme.colorScheme;
    final initial = (user.displayName ?? user.email ?? '?')
        .replaceAll(RegExp(r'[^A-Za-zČčĆćĐđŠšŽž]'), '')
        .characters
        .firstOrNull
        ?.toUpperCase() ??
        '?';
    return _card(
      theme,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: cs.primary,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName ?? 'Korisnik',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (user.email != null)
                    Text(
                      user.email!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  if (user.isVerified)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, size: 14, color: cs.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Verificiran identitet (eOsobna)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identitiesCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final providers = AuthService.instance.linkedProviders;
    return _card(
      theme,
      child: Column(
        children: [
          if (providers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nema povezanih prijavnih metoda.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            ...providers.map((p) => ListTile(
                  leading: Icon(_providerIcon(p), color: cs.primary),
                  title: Text(p.displayName),
                  subtitle: Text(_providerSubtitle(p)),
                  dense: true,
                )),
        ],
      ),
    );
  }

  IconData _providerIcon(AuthProvider p) => switch (p) {
        AuthProvider.google => Icons.g_mobiledata,
        AuthProvider.apple => Icons.apple,
        AuthProvider.email => Icons.alternate_email,
        AuthProvider.passkey => Icons.fingerprint,
        AuthProvider.certilia => Icons.badge_outlined,
      };

  String _providerSubtitle(AuthProvider p) => switch (p) {
        AuthProvider.google => 'Google račun',
        AuthProvider.apple => 'Apple račun',
        AuthProvider.email => 'Magic link / kod na e-mail',
        AuthProvider.passkey => 'Passkey',
        AuthProvider.certilia => 'Hrvatska e-osobna (Certilia / NIAS)',
      };

  Widget _passkeysCard(ThemeData theme) {
    final cs = theme.colorScheme;
    return _card(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_passkeysLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_passkeysUnsupported)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Pregled i uklanjanje passkeyja stiže uskoro. Novi passkey '
                'možeš dodati već sada.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else if (_passkeysError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: cs.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _passkeysError!,
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: cs.error),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadPasskeys,
                    child: const Text('Ponovi'),
                  ),
                ],
              ),
            )
          else if (_passkeys == null || _passkeys!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nemaš registriranih passkeyja. Passkey je najsigurniji i '
                'najbrži način prijave — bez lozinke, uz Face ID / otisak.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            ..._passkeys!.map((pk) => ListTile(
                  leading: Icon(Icons.fingerprint, color: cs.primary),
                  title: Text(pk.deviceName ?? 'Passkey'),
                  subtitle: Text(_passkeyMeta(pk)),
                  dense: true,
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error, size: 20),
                    tooltip: 'Ukloni passkey',
                    onPressed: () => _confirmDeletePasskey(pk),
                  ),
                )),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Dodaj passkey na ovom uređaju'),
              onPressed: _addPasskey,
            ),
          ),
        ],
      ),
    );
  }

  String _passkeyMeta(PasskeyInfo pk) {
    final created = pk.createdAt;
    final used = pk.lastUsedAt;
    final parts = <String>[
      if (created != null)
        'dodan ${created.day}.${created.month}.${created.year}.',
      if (used != null)
        'zadnje korišten ${used.day}.${used.month}.${used.year}.',
    ];
    return parts.isEmpty ? 'Passkey' : parts.join(' · ');
  }

  Future<void> _addPasskey() async {
    final result = await AuthService.instance
        .linkIdentity(context, AuthProvider.passkey);
    if (!mounted) return;
    switch (result.status) {
      case AuthFlowStatus.success:
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(result.message ?? 'Passkey je dodan.')),
        );
        _loadPasskeys();
      case AuthFlowStatus.failure:
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(result.message ?? 'Passkey nije dodan.')),
        );
      case AuthFlowStatus.redirect:
      case AuthFlowStatus.emailSent:
      case AuthFlowStatus.cancelled:
        break;
    }
  }

  Future<void> _confirmDeletePasskey(PasskeyInfo pk) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ukloniti passkey?'),
        content: Text(
          '„${pk.deviceName ?? 'Passkey'}" više neće moći prijaviti ovaj '
          'račun. Ova radnja je trajna.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ukloni'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await PasskeyService.instance.deletePasskey(pk.id);
      if (!mounted) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Passkey je uklonjen.')),
      );
      _loadPasskeys();
    } on PasskeyFailure catch (e) {
      if (!mounted) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Widget _devicesCard(ThemeData theme) {
    return _card(
      theme,
      child: ListTile(
        leading:
            Icon(Icons.devices_other, color: theme.colorScheme.primary),
        title: const Text('Prebaci na drugi uređaj'),
        subtitle: const Text('Generiraj kod i prijavi se na TV-u ili mobitelu'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: () => context.go('/handoff'),
      ),
    );
  }

  Widget _signOutCard(ThemeData theme) {
    return _card(
      theme,
      child: ListTile(
        leading: Icon(Icons.logout, color: theme.colorScheme.onSurfaceVariant),
        title: const Text('Odjavi se'),
        subtitle: const Text('Nastavljaš kao gost — podaci ostaju na računu'),
        onTap: () => confirmAndSignOut(context),
      ),
    );
  }

  Widget _dangerCard(ThemeData theme) {
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        leading: Icon(Icons.delete_forever_outlined, color: cs.error),
        title: Text('Izbriši račun', style: TextStyle(color: cs.error)),
        subtitle: const Text(
          'Trajno briše račun, favorite, napredak i sve povezane podatke.',
        ),
        trailing: _deleting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: _deleting ? null : _confirmDeleteAccount,
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final result = await AuthService.instance.deleteAccount();
    if (!mounted) return;
    setState(() => _deleting = false);

    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(result.message ??
            (result.status == AuthFlowStatus.success
                ? 'Račun je izbrisan.'
                : 'Brisanje nije uspjelo.')),
        duration: const Duration(seconds: 5),
      ),
    );
    if (result.status == AuthFlowStatus.success) {
      context.go('/');
    }
  }
}

/// Potvrda odjave — dijeli ju AccountChip menu i Moj račun ekran.
Future<void> confirmAndSignOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Odjaviti se?'),
      content: const Text(
        'Tvoj napredak i favoriti ostaju spremljeni na računu — '
        'vraćaju se kad se ponovno prijaviš.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Odjavi se'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await AuthService.instance.signOut(context);
  }
}

/// Type-to-confirm dialog za trajno brisanje računa.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  static const _confirmWord = 'IZBRIŠI';
  final _ctrl = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AlertDialog(
      title: const Text('Trajno izbrisati račun?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Brišu se račun, favoriti, napredak gledanja, passkeyji i sve '
            'povezane postavke. Ova radnja je nepovratna.\n\n'
            'Za potvrdu upiši IZBRIŠI:',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (v) => setState(
                () => _matches = v.trim().toUpperCase() == _confirmWord),
            decoration: const InputDecoration(
              hintText: _confirmWord,
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Odustani'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cs.error),
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: const Text('Trajno izbriši'),
        ),
      ],
    );
  }
}
