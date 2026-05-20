/// Shared bottom sheet za sign-in. Pokazuje 4 providera (Passkey first, Google,
/// Apple, e-mail magic link). U mocku svaki gumb okida AuthService.linkIdentity()
/// koji prikazuje SnackBar i postavi user kao logged-in.
library;

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

const _croRed = Color(0xFFFF0000);
const _croBlue = Color(0xFF002F6C);

enum AuthSheetOrigin { account, moment2, moment3, handoff }

Future<void> showAuthSheet(
  BuildContext context, {
  AuthSheetOrigin origin = AuthSheetOrigin.account,
  String? headlineOverride,
  String? subtitleOverride,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AuthSheetContent(
      origin: origin,
      headlineOverride: headlineOverride,
      subtitleOverride: subtitleOverride,
    ),
  );
}

class _AuthSheetContent extends StatelessWidget {
  final AuthSheetOrigin origin;
  final String? headlineOverride;
  final String? subtitleOverride;

  const _AuthSheetContent({
    required this.origin,
    this.headlineOverride,
    this.subtitleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headline = headlineOverride ?? _defaultHeadline();
    final subtitle = subtitleOverride ?? _defaultSubtitle();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              headline,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: _croBlue,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _ProviderButton(
              icon: Icons.fingerprint,
              label: 'Passkey',
              subtitle: 'Najsigurnije, bez lozinke',
              accent: _croBlue,
              isPrimary: true,
              onTap: () => _doLink(context, AuthProvider.passkey),
            ),
            const SizedBox(height: 10),
            _ProviderButton(
              icon: Icons.account_circle,
              label: 'Nastavi s Google računom',
              accent: const Color(0xFFEA4335),
              onTap: () => _doLink(context, AuthProvider.google),
            ),
            const SizedBox(height: 10),
            _ProviderButton(
              icon: Icons.apple,
              label: 'Nastavi s Apple ID',
              accent: theme.brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
              onTap: () => _doLink(context, AuthProvider.apple),
            ),
            const SizedBox(height: 10),
            _ProviderButton(
              icon: Icons.mail_outline,
              label: 'E-mail magic link',
              accent: theme.colorScheme.onSurfaceVariant,
              onTap: () => _doLink(context, AuthProvider.email),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _croBlue.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _croBlue.withAlpha(40)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: _croBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tvoj trenutni napredak ostaje sačuvan i povezuje se s računom.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                origin == AuthSheetOrigin.moment2
                    ? 'Možda kasnije'
                    : 'Zatvori',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _defaultHeadline() => switch (origin) {
        AuthSheetOrigin.account => 'Prijavi se na DOMOVINA.ai',
        AuthSheetOrigin.moment2 =>
          'Spremi napredak na sve uređaje',
        AuthSheetOrigin.moment3 =>
          'Spremi favorite u svoj račun',
        AuthSheetOrigin.handoff =>
          'Završi prijavu na ovom uređaju',
      };

  String _defaultSubtitle() => switch (origin) {
        AuthSheetOrigin.account =>
          'Bez lozinke. Passkey ili tvoj postojeći Google/Apple račun.',
        AuthSheetOrigin.moment2 =>
          'Trenutno tvoja pozicija reprodukcije ostaje samo na ovom uređaju.',
        AuthSheetOrigin.moment3 =>
          'Da favoriti ostanu dostupni na svim tvojim uređajima.',
        AuthSheetOrigin.handoff =>
          'Kod je verificiran — odaberi kako želiš nastaviti.',
      };

  Future<void> _doLink(BuildContext context, AuthProvider p) async {
    Navigator.of(context).pop();
    await AuthService.instance.linkIdentity(context, p);
  }
}

class _ProviderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color accent;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ProviderButton({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.accent,
    this.isPrimary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isPrimary
        ? accent.withAlpha(20)
        : theme.colorScheme.surfaceContainerHighest.withAlpha(120);
    final border = isPrimary ? accent : theme.colorScheme.outlineVariant;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: isPrimary ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (isPrimary)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _croRed,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'PREPORUČENO',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
