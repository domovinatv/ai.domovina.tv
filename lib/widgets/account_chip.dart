/// Avatar chip u home header-u — klikom otvara auth sheet (anonimni)
/// ili menu (logged-in).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../onboarding/ui/auth_sheet.dart';
import '../screens/account/account_screen.dart' show confirmAndSignOut;
import '../services/auth_service.dart';
import '../theme/app_theme.dart';


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
            verified: auth.currentUser?.isVerified ?? false,
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
    final l = AppLocalizations.of(context);
    // Filled BRAND navy pill (#002F6C) — ne cs.primary, jer ga M3 u dark temi
    // tonalno pomakne u blijedo-plavo (tone 80) pa bijeli tekst na njemu
    // izgleda isprano. Fiksna zastavna navy + svjetliji rub da se odvoji od
    // tamne pozadine; u light temi rub se ne crta (navy na cream-u već čita).
    return Material(
      color: AppTheme.croBlue,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: AppTheme.brandRim(theme.brightness),
      ),
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
                l.commonSignIn,
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
  final bool verified;

  const _SignedInChip({
    this.displayName,
    this.email,
    this.provider,
    this.verified = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
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
                displayName ?? l.mediaUserFallback,
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
                  l.mediaViaProvider(provider!.displayName),
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (verified)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified,
                          size: 13, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        l.mediaVerifiedIdentity,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'account',
          child: ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: Text(l.mediaMyAccount),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'channels',
          child: ListTile(
            leading: const Icon(Icons.smart_display_outlined),
            title: Text(l.mediaMyChannels),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'handoff',
          child: ListTile(
            leading: const Icon(Icons.devices_other),
            title: Text(l.mediaSwitchDevice),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'signout',
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l.commonSignOut),
            dense: true,
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Brand navy avatar (ne cs.primary — vidi _AnonymousChip komentar).
            // Suptilni rub u dark temi da se krug odvoji od tamne pozadine.
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  AppTheme.brandRim(theme.brightness),
                ),
              ),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.croBlue,
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
            // KYC: verificirani identitet (eID) → plavi check badge.
            if (verified)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(1),
                  child: Icon(
                    Icons.verified,
                    size: 13,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onSelected(BuildContext context, String value) {
    switch (value) {
      case 'account':
        context.go('/account');
        break;
      case 'channels':
        context.go('/account/channels');
        break;
      case 'handoff':
        context.go('/handoff');
        break;
      case 'signout':
        confirmAndSignOut(context);
        break;
    }
  }
}
