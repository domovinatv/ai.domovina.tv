/// Trajna, neprekidajuća "gost" traka na dnu ekrana epizode.
///
/// Zamjena za stari M2 modal koji je nakon 30 s slušanja sam iskakao preko
/// videa. Ista mehanika kao `PinkaSupportBar` (sticky bottom, ne prekida
/// reprodukciju): korisnik u svakom trenutku vidi da je anoniman i ima
/// jednoklik CTA — ali sam bira kada.
///
/// Sama se sakrije čim je korisnik prijavljen (sluša `AuthService`).
library;

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../onboarding/ui/auth_sheet.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class AnonymousSignInBar extends StatelessWidget {
  /// Traka je najniži element na ekranu → sama respektira donji notch/gestu.
  final bool applyBottomSafeArea;

  const AnonymousSignInBar({super.key, this.applyBottomSafeArea = true});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        if (!AuthService.instance.isAnonymous) return const SizedBox.shrink();
        return _Bar(applyBottomSafeArea: applyBottomSafeArea);
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final bool applyBottomSafeArea;
  const _Bar({required this.applyBottomSafeArea});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    // Uski ekrani: podnaslov pada van, ostaje naslov + CTA (isti prag kao
    // PinkaSupportBar da se dvije trake vizualno slažu).
    final narrow = MediaQuery.sizeOf(context).width < 420;

    return Material(
      color: cs.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        bottom: applyBottomSafeArea,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: InkWell(
            onTap: () => showAuthSheet(context, origin: AuthSheetOrigin.guest),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.person_outline, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.authGuestBarTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (!narrow)
                          Text(
                            l.authGuestBarBody,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Brand navy fill (ne cs.primary — M3 ga u dark temi pomakne
                  // u blijedo-plavo pa bijeli tekst izgleda isprano).
                  FilledButton(
                    onPressed: () =>
                        showAuthSheet(context, origin: AuthSheetOrigin.guest),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.croBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      side: AppTheme.brandRim(theme.brightness),
                    ),
                    child: Text(l.commonSignIn),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
