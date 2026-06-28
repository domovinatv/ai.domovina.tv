/// Supporter identity reward — a small "PLUS" chip shown for DOMOVINA Plus
/// subscribers. Brand navy fill + brandRim per theme conventions (navy FILL =
/// AppTheme.croBlue, never cs.primary). Additive only — never gates content.
library;

import 'package:flutter/material.dart';
import '../services/entitlement_service.dart';
import '../theme/app_theme.dart';

/// Static visual chip. Render directly when you already know the user is Plus.
class PlusBadge extends StatelessWidget {
  final double fontSize;
  const PlusBadge({super.key, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.croBlue,
        borderRadius: BorderRadius.circular(999),
        border: Border.fromBorderSide(AppTheme.brandRim(Theme.of(context).brightness)),
      ),
      child: Text(
        'PLUS',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

/// Reactive variant — shows the [PlusBadge] only while the entitlement is
/// active, and nothing otherwise. Safe to drop anywhere.
class PlusBadgeIfActive extends StatelessWidget {
  final double fontSize;
  const PlusBadgeIfActive({super.key, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EntitlementService.instance.isPlus,
      builder: (context, isPlus, _) =>
          isPlus ? PlusBadge(fontSize: fontSize) : const SizedBox.shrink(),
    );
  }
}
