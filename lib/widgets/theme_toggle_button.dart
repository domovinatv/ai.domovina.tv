import 'package:flutter/material.dart';

import '../services/theme_mode_service.dart';

/// Sunce/mjesec ikona u home app baru — prebacuje tamnu ↔ svijetlu temu.
/// Vidljiva svima (i anonimnim korisnicima); odluka se sprema lokalno.
///
/// Ikona prikazuje temu na koju ce se PREBACITI (mjesec kad si u svijetloj,
/// sunce kad si u tamnoj) — standardni pattern za theme toggle.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        final isDark = ThemeController.instance.isDark;
        return IconButton(
          icon: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            size: 20,
          ),
          tooltip:
              isDark ? 'Prebaci na svijetlu temu' : 'Prebaci na tamnu temu',
          onPressed: ThemeController.instance.toggle,
        );
      },
    );
  }
}
