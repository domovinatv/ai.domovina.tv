import 'package:flutter/material.dart';
import 'typography.dart';

/// Centralizirani ThemeData za DOMOVINA.ai.
///
/// Korak 1 redizajna — premiestio iz inline definicija u main.dart.
/// Croatian navy (#002F6C) kao seed, crveni akcent (#FF0000) za call-to-action.
/// Editorial typography preko AppTypography.
class AppTheme {
  AppTheme._();

  /// Croatian flag colours.
  static const Color croRed = Color(0xFFFF0000);
  static const Color croBlue = Color(0xFF002F6C);

  /// Off-white pozadina za editorial light mode — toplija od bijelog,
  /// daje "papir" osjećaj koji odgovara serif typography-ju.
  static const Color _surfaceCream = Color(0xFFFAF7F2);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: croBlue,
      brightness: Brightness.light,
    ).copyWith(
      // Surface tonovi — cream papir za editorial look.
      surface: _surfaceCream,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF5F1EA),
      surfaceContainer: const Color(0xFFEEE9DF),
      // Crveni akcent za CTA ostaje (.ai sufiks, hero "Slušaj" gumb).
      tertiary: croRed,
      onTertiary: Colors.white,
    );
    return _build(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: croBlue,
      brightness: Brightness.dark,
    ).copyWith(
      tertiary: croRed,
      onTertiary: Colors.white,
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    final textTheme = AppTypography.textTheme(scheme);

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: AppTypography.wordmarkStyle(
          color: scheme.onSurface,
          fontSize: 20,
        ),
      ),

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: croBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
        space: 1,
      ),

      iconTheme: IconThemeData(
        color: scheme.onSurface,
        size: 20,
      ),
    );
  }
}
