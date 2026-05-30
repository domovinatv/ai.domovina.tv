import 'package:flutter/material.dart';

/// Renderira Meili `_formatted` string (s `<em>…</em>` highlight tagovima) kao
/// rich text — matchani dijelovi crveno + bold. Meili je autoritativan izvor
/// highlighta (typo-tolerantni matchevi koje lokalni highlighter ne bi uhvatio).
class EmHighlightText extends StatelessWidget {
  final String formatted;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int? maxLines;
  final TextOverflow overflow;

  const EmHighlightText(
    this.formatted, {
    this.style,
    this.highlightStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final red = theme.brightness == Brightness.dark
        ? const Color(0xFFFF6B6B)
        : const Color(0xFFD32F2F);
    final hl = highlightStyle ??
        (style ?? const TextStyle())
            .copyWith(color: red, fontWeight: FontWeight.w700);

    final spans = <TextSpan>[];
    var rest = formatted;
    while (true) {
      final open = rest.indexOf('<em>');
      if (open < 0) {
        if (rest.isNotEmpty) spans.add(TextSpan(text: rest, style: style));
        break;
      }
      if (open > 0) {
        spans.add(TextSpan(text: rest.substring(0, open), style: style));
      }
      final close = rest.indexOf('</em>', open + 4);
      if (close < 0) {
        // Nezatvoreni tag — tretiraj ostatak kao plain.
        spans.add(TextSpan(text: rest.substring(open + 4), style: style));
        break;
      }
      spans.add(TextSpan(text: rest.substring(open + 4, close), style: hl));
      rest = rest.substring(close + 5);
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
