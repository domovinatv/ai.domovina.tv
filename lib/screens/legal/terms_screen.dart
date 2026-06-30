import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'legal_page_scaffold.dart';

/// Placeholder za /terms — potreban za Google OAuth consent screen.
/// Konacni tekst dolazi kasnije.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.6);

    return LegalPageScaffold(
      title: l.legalTermsTitle,
      children: [
        Text(
          l.legalLastUpdated('26. svibnja 2026.'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l.legalTermsIntro,
          style: body,
        ),
        const SizedBox(height: 24),
        Text(l.legalTermsContentTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          l.legalTermsContentBody,
          style: body,
        ),
        const SizedBox(height: 24),
        Text(l.legalTermsAiTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          l.legalTermsAiBody,
          style: body,
        ),
        const SizedBox(height: 24),
        Text(l.legalContactTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          l.legalTermsContactBody,
          style: body,
        ),
        const SizedBox(height: 48),
      ],
    );
  }
}
