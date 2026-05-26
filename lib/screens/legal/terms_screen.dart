import 'package:flutter/material.dart';
import 'legal_page_scaffold.dart';

/// Placeholder za /terms — potreban za Google OAuth consent screen.
/// Konacni tekst dolazi kasnije.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.6);

    return LegalPageScaffold(
      title: 'Uvjeti koristenja',
      children: [
        Text(
          'Zadnje azurirano: 26. svibnja 2026.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Koristenjem aplikacije DOMOVINA.ai prihvacate ove uvjete. Ova '
          'stranica je placeholder za potpune uvjete koristenja.',
          style: body,
        ),
        const SizedBox(height: 24),
        Text('Sadrzaj', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Sadrzaj epizoda (video, transkripti, sazeci) prikazuje se u '
          'edukativne svrhe. Autorska prava nad originalnim podcastima '
          'pripadaju njihovim autorima i kanalima.',
          style: body,
        ),
        const SizedBox(height: 24),
        Text('AI analiza', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Magisterium AI ocjene i sazeci su generirani strojno i mogu '
          'sadrzavati pogreske. Ne predstavljaju sluzbeno stajaliste '
          'Katolicke Crkve.',
          style: body,
        ),
        const SizedBox(height: 24),
        Text('Kontakt', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Za pitanja se javite na stepanic.matija@gmail.com.',
          style: body,
        ),
        const SizedBox(height: 48),
      ],
    );
  }
}
