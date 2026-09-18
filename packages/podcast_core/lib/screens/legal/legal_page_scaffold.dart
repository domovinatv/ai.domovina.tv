import 'package:flutter/material.dart';
import '../../router/nav.dart';

/// Zajednicki scaffold za /privacy i /terms placeholder stranice.
/// Drzi konzistentan layout (max-width 760, app bar s back na /) dok
/// se konacni pravni tekstovi ne pripreme.
class LegalPageScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const LegalPageScaffold({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            back(context);
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
