import 'package:flutter/material.dart';

/// Non-intrusive chip koji epizoda pokaže kratko (~4s) kad player auto-resumea
/// s zadnje pozicije. Nema gumba — korisnik ako želi rewind, koristi player
/// kontrole. Inline u widget tree-u screena (ne SnackBar) tako da se uništi
/// pri navigaciji back i nikad ne "lingera" preko sljedećeg ekrana.
class ResumeHintBanner extends StatelessWidget {
  final int seconds;

  const ResumeHintBanner({super.key, required this.seconds});

  String get _label {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String p(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${p(m)}:${p(s)}' : '$m:${p(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.inverseSurface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle_outline,
                size: 18,
                color: theme.colorScheme.onInverseSurface,
              ),
              const SizedBox(width: 8),
              Text(
                'Nastavljam s $_label',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onInverseSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
