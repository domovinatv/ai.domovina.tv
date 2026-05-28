/// Premium sign-in bottom sheet. Brandiran (logo + trikolora + editorial
/// typography); nudi Passkey (preporučeno) + Google/Apple/e-mail magic link,
/// te "Već imaš passkey? Prijavi se".
library;

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import 'auth_ui.dart';

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
    barrierColor: Colors.black.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
    final cs = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 4,
            bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthBrandHeader(
                  title: headlineOverride ?? _defaultHeadline(),
                  subtitle: subtitleOverride ?? _defaultSubtitle(),
                ),
                const SizedBox(height: 24),

                // Passkey — preporučena metoda.
                AuthProviderTile(
                  primary: true,
                  badge: 'PREPORUČENO',
                  iconBg: Colors.white.withValues(alpha: 0.16),
                  iconChild: const Icon(Icons.fingerprint,
                      color: Colors.white, size: 22),
                  label: 'Kreiraj passkey',
                  subtitle: 'Najsigurnije — bez lozinke, uz Face ID / otisak',
                  onTap: () => _doLink(context, AuthProvider.passkey),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: () async {
                      await AuthService.instance.signInWithPasskey(context);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: cs.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Već imaš passkey? Prijavi se'),
                  ),
                ),

                const SizedBox(height: 12),
                const LabeledDivider(),
                const SizedBox(height: 16),

                AuthProviderTile(
                  iconBg: const Color(0xFFF1F3F4),
                  iconChild: const Text(
                    'G',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 19,
                      color: Color(0xFF4285F4),
                      height: 1,
                    ),
                  ),
                  label: 'Nastavi s Google računom',
                  onTap: () => _doLink(context, AuthProvider.google),
                ),
                const SizedBox(height: 10),
                AuthProviderTile(
                  iconBg: const Color(0xFF111111),
                  iconChild:
                      const Icon(Icons.apple, color: Colors.white, size: 24),
                  label: 'Nastavi s Apple ID',
                  onTap: () => _doLink(context, AuthProvider.apple),
                ),
                const SizedBox(height: 10),
                AuthProviderTile(
                  iconBg: AppTheme.croBlue.withValues(alpha: 0.10),
                  iconChild: const Icon(Icons.alternate_email,
                      color: AppTheme.croBlue, size: 21),
                  label: 'E-mail magic link',
                  subtitle: 'Pošaljemo ti link i kod za prijavu',
                  onTap: () => _doLink(context, AuthProvider.email),
                ),
                const SizedBox(height: 10),
                AuthProviderTile(
                  iconBg: AppTheme.croRed.withValues(alpha: 0.10),
                  iconChild: const Icon(Icons.badge_outlined,
                      color: AppTheme.croRed, size: 22),
                  label: 'Prijava eOsobnom',
                  subtitle: 'Hrvatska e-osobna (Certilia / NIAS)',
                  onTap: () => _doLink(context, AuthProvider.certilia),
                ),

                const SizedBox(height: 18),
                _ReassuranceNote(origin: origin),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    origin == AuthSheetOrigin.moment2 ? 'Možda kasnije' : 'Zatvori',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _defaultHeadline() => switch (origin) {
        AuthSheetOrigin.account => 'Prijavi se na DOMOVINA.ai',
        AuthSheetOrigin.moment2 => 'Spremi napredak na sve uređaje',
        AuthSheetOrigin.moment3 => 'Spremi favorite u svoj račun',
        AuthSheetOrigin.handoff => 'Završi prijavu na ovom uređaju',
      };

  String _defaultSubtitle() => switch (origin) {
        AuthSheetOrigin.account =>
          'Bez lozinke. Passkey ili tvoj postojeći Google / Apple račun.',
        AuthSheetOrigin.moment2 =>
          'Trenutno tvoja pozicija reprodukcije ostaje samo na ovom uređaju.',
        AuthSheetOrigin.moment3 =>
          'Da favoriti ostanu dostupni na svim tvojim uređajima.',
        AuthSheetOrigin.handoff =>
          'Kod je verificiran — odaberi kako želiš nastaviti.',
      };

  Future<void> _doLink(BuildContext context, AuthProvider p) async {
    // NE popati sheet prije async rada — context bi se unmountao pa bi
    // linkIdentity rano izašao na `context.mounted` guardu. Sheet ostaje
    // otvoren tijekom operacije (dialozi/WebAuthn idu preko njega), pop poslije.
    await AuthService.instance.linkIdentity(context, p);
    if (context.mounted) Navigator.of(context).pop();
  }
}

/// Suptilna "papirnata" napomena o privatnosti / čuvanju napretka.
class _ReassuranceNote extends StatelessWidget {
  final AuthSheetOrigin origin;
  const _ReassuranceNote({required this.origin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 17, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tvoj trenutni napredak ostaje sačuvan i sigurno se povezuje s računom.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
