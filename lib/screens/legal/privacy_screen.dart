import 'package:flutter/material.dart';
import 'legal_page_scaffold.dart';

/// Placeholder za /privacy — potreban za Google OAuth consent screen.
/// Konacni tekst dolazi kasnije; trenutno samo opisuje sto se sprema.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.6);

    return LegalPageScaffold(
      title: 'Politika privatnosti',
      children: [
        Text(
          'Zadnje azurirano: 26. svibnja 2026.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'DOMOVINA.ai je aplikacija koja transkribira, sazima i analizira '
          'hrvatske katolicke podcaste pomocu umjetne inteligencije. Ova '
          'stranica je placeholder za potpunu politiku privatnosti.',
          style: body,
        ),
        const SizedBox(height: 24),
        Text('Koje podatke prikupljamo',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Ako se prijavite Google racunom, prikupljamo email adresu i ime '
          'koje Google posalje aplikaciji. Pohranjujemo i napredak gledanja '
          'epizoda te oznake favorita kako bismo ih sinkronizirali izmedju '
          'uredjaja.',
          style: body,
        ),
        const SizedBox(height: 24),
        Text('Kontakt', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Za pitanja vezana uz privatnost javite se na '
          'stepanic.matija@gmail.com.',
          style: body,
        ),
        const SizedBox(height: 48),
      ],
    );
  }
}
