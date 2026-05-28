/// Avatar chip u home header-u — klikom otvara auth sheet (anonimni)
/// ili menu (logged-in).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../onboarding/ui/auth_sheet.dart';
import '../services/auth_service.dart';


class AccountChip extends StatelessWidget {
  const AccountChip({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        final auth = AuthService.instance;
        if (auth.isSignedIn) {
          return _SignedInChip(
            displayName: auth.currentUser?.displayName,
            email: auth.currentUser?.email,
            provider: auth.currentUser?.provider,
          );
        }
        return _AnonymousChip();
      },
    );
  }
}

class _AnonymousChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Filled navy pill — visok kontrast na cream/dark surface (raniji "Prijava"
    // u bijelom na transparentnom bio je nevidljiv na svijetloj pozadini).
    return Material(
      color: cs.primary,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAuthSheet(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline,
                    size: 14, color: Colors.white),
              ),
              const SizedBox(width: 7),
              Text(
                'Prijava',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignedInChip extends StatelessWidget {
  final String? displayName;
  final String? email;
  final AuthProvider? provider;

  const _SignedInChip({this.displayName, this.email, this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = (displayName ?? email ?? '?')
        .replaceAll(RegExp(r'[^A-Za-zČčĆćĐđŠšŽž]'), '')
        .characters
        .firstOrNull?.toUpperCase() ?? '?';

    return PopupMenuButton<String>(
      tooltip: displayName ?? email,
      offset: const Offset(0, 36),
      onSelected: (v) => _onSelected(context, v),
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'info',
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName ?? 'Korisnik',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (email != null)
                Text(
                  email!,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (provider != null)
                Text(
                  'preko ${provider!.displayName}',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'handoff',
          child: ListTile(
            leading: Icon(Icons.devices_other),
            title: Text('Prebaci na drugi uređaj'),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'signout',
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('Odjavi se'),
            dense: true,
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.primary,
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  void _onSelected(BuildContext context, String value) {
    switch (value) {
      case 'handoff':
        context.go('/handoff');
        break;
      case 'signout':
        AuthService.instance.signOut(context);
        break;
    }
  }
}
