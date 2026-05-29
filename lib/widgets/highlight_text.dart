import 'package:flutter/material.dart';

import '../utils/text_search.dart';

/// Tekst s istaknutim (crveno + bold) dijelovima koji odgovaraju [query]-ju.
///
/// Dijakritik-neosjetljivo (preko [highlightRanges]). Ako nema podudaranja
/// (ili je query prazan), ponaša se kao običan [Text].
class QueryHighlightText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int? maxLines;
  final TextOverflow overflow;

  const QueryHighlightText(
    this.text, {
    required this.query,
    this.style,
    this.highlightStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ranges = highlightRanges(text, query);
    if (ranges.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final theme = Theme.of(context);
    final red = theme.brightness == Brightness.dark
        ? const Color(0xFFFF6B6B)
        : const Color(0xFFD32F2F);
    final hl = highlightStyle ??
        (style ?? const TextStyle()).copyWith(
          color: red,
          fontWeight: FontWeight.w700,
        );

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final r in ranges) {
      final s = r[0], e = r[1];
      if (s > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, s), style: style));
      }
      spans.add(TextSpan(text: text.substring(s, e), style: hl));
      cursor = e;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
