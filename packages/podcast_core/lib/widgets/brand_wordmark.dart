import 'package:flutter/material.dart';

import '../brand/app_brand.dart';
import '../theme/typography.dart';

/// Wordmark brenda — `BrandConfig.wordmark` + `wordmarkAccent` u jednom
/// `Text.rich`-u, Playfair 800 (`AppTypography.wordmarkStyle`).
///
/// Za DOMOVINA.ai: "DOMOVINA" u [color] + ".ai" u [accentColor]
/// (zadano `colorScheme.tertiary`, tj. crveni akcent). Prazan
/// `wordmarkAccent` ne crta drugi span. Jedini widget koji crta wordmark —
/// koriste ga home app bar i auth sheet/callback ekran.
class BrandWordmark extends StatelessWidget {
  /// Boja osnovnog dijela; zadano `colorScheme.onSurface`.
  final Color? color;

  /// Boja naglašenog sufiksa; zadano `colorScheme.tertiary`.
  final Color? accentColor;

  final double fontSize;

  const BrandWordmark({
    super.key,
    this.color,
    this.accentColor,
    this.fontSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = AppBrand.config;
    final base = AppTypography.wordmarkStyle(
      color: color ?? scheme.onSurface,
      fontSize: fontSize,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: brand.wordmark),
          if (brand.wordmarkAccent.isNotEmpty)
            TextSpan(
              text: brand.wordmarkAccent,
              style: TextStyle(color: accentColor ?? scheme.tertiary),
            ),
        ],
      ),
    );
  }
}
