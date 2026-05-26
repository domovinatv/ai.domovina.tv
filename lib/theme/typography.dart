import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Editorial typography za DOMOVINA.ai homepage redesign.
///
/// Strategija: na web koristimo direktan fontFamily string (browser dohvaća
/// font preko `<link>` u web/index.html — brže, bez runtime downloada). Na
/// native (iOS/Android/macOS) koristimo `google_fonts` paket koji handle-a
/// caching i fallback.
///
/// Vidi web/index.html za font load deklaraciju i Korak 1 plana redizajna.
class AppTypography {
  static const _playfair = 'Playfair Display';
  static const _lora = 'Lora';
  static const _inter = 'Inter';

  /// Vraća TextStyle s odgovarajućim fontom — web koristi fontFamily string,
  /// native koristi GoogleFonts wrapper.
  static TextStyle _playfairStyle({
    required double fontSize,
    required FontWeight fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    if (kIsWeb) {
      return TextStyle(
        fontFamily: _playfair,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
    return GoogleFonts.playfairDisplay(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle _loraStyle({
    required double fontSize,
    required FontWeight fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    if (kIsWeb) {
      return TextStyle(
        fontFamily: _lora,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
    return GoogleFonts.lora(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle _interStyle({
    required double fontSize,
    required FontWeight fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    if (kIsWeb) {
      return TextStyle(
        fontFamily: _inter,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Material 3 TextTheme mapping. Display + headline koriste Playfair
  /// (editorial), title + label + bodyMedium/Small koriste Inter (UI), a
  /// bodyLarge koristi Lora (serif za long-form text poput hero opisa).
  static TextTheme textTheme(ColorScheme scheme) {
    final onSurface = scheme.onSurface;

    return TextTheme(
      // Hero / display
      displayLarge: _playfairStyle(
        fontSize: 56,
        fontWeight: FontWeight.w800,
        color: onSurface,
        height: 1.05,
        letterSpacing: -0.5,
      ),
      displayMedium: _playfairStyle(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.1,
        letterSpacing: -0.3,
      ),
      displaySmall: _playfairStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.15,
      ),

      // Section headlines, channel card titles
      headlineLarge: _playfairStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.2,
      ),
      headlineMedium: _playfairStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.25,
      ),
      headlineSmall: _playfairStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: onSurface,
        height: 1.3,
      ),

      // Titles (UI sans-serif)
      titleLarge: _interStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: onSurface,
        height: 1.3,
      ),
      titleMedium: _interStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurface,
        height: 1.35,
        letterSpacing: 0.1,
      ),
      titleSmall: _interStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: onSurface,
        height: 1.4,
        letterSpacing: 0.1,
      ),

      // Body — bodyLarge je serif (Lora) za hero description / editorial body.
      bodyLarge: _loraStyle(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        color: onSurface,
        height: 1.55,
      ),
      bodyMedium: _interStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: onSurface,
        height: 1.5,
        letterSpacing: 0.15,
      ),
      bodySmall: _interStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
        height: 1.45,
        letterSpacing: 0.2,
      ),

      // Labels — buttons, chips, all-caps section eyebrows.
      labelLarge: _interStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: 0.3,
      ),
      labelMedium: _interStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: onSurface,
        letterSpacing: 0.5,
      ),
      // labelSmall se koristi kao "eyebrow" all-caps oznaka iznad sekcija
      // (npr. "ISTAKNUTO", "NASTAVI SLUŠATI"). Veliki letterSpacing.
      labelSmall: _interStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
        letterSpacing: 1.4,
      ),
    );
  }

  /// Wordmark stil za "DOMOVINA.ai" u app baru (Playfair 800).
  static TextStyle wordmarkStyle({required Color color, double fontSize = 22}) {
    return _playfairStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: 0.5,
    );
  }

  /// Eyebrow stil — all-caps mala oznaka iznad sekcija ("ISTAKNUTO").
  static TextStyle eyebrowStyle(ColorScheme scheme) {
    return _interStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
      letterSpacing: 1.6,
    );
  }
}
