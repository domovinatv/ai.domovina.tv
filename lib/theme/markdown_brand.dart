import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'app_theme.dart';

/// Brand stil za markdown blockquote — puna navy ploha s bijelim tekstom.
///
/// flutter_markdown default je `Colors.blue.shade100` (baby-blue) fill, na
/// kojem je tekst u dark temi (bijeli bodyMedium) nečitljiv. Navy brand-fill
/// pravilo: `AppTheme.croBlue` + `brandRim()`, nikad `cs.primary`.
extension BrandBlockquote on MarkdownStyleSheet {
  MarkdownStyleSheet withBrandBlockquote(ThemeData theme) => copyWith(
        blockquote: (blockquote ?? theme.textTheme.bodyMedium)?.copyWith(
          color: Colors.white,
          height: 1.55,
        ),
        blockquoteDecoration: BoxDecoration(
          color: AppTheme.croBlue,
          borderRadius: BorderRadius.circular(8),
          border: Border.fromBorderSide(AppTheme.brandRim(theme.brightness)),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      );
}
