/// Avatar chip u home header-u — klikom otvara auth sheet (anonimni)
/// ili menu (logged-in).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../onboarding/ui/auth_sheet.dart';
import '../services/auth_service.dart';

const _croBlue = Color(0xFF002F6C);
const _croRed = Color(0xFFFF0000);

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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showAuthSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _croBlue.withAlpha(80)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.person_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _croRed,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        '?',
                        style: TextStyle(
                          fontSize: 7,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Text(
                'Prijava',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _croBlue,
                  fontWeight: FontWeight.w600,
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
          backgroundColor: _croBlue,
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
