library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../l10n/app_localizations.dart';

/// Kopiraj-redak (label + monospace vrijednost + copy gumb) za IBAN/adresu/memo.
class PinkaCopyRow extends StatelessWidget {
  final String label;
  final String value;
  final double labelWidth;

  /// Kad je postavljen, copy gumb kopira OVU vrijednost, a [value] je samo
  /// prikaz (npr. IBAN grupiran razmacima za čitanje, kompaktan za lijepljenje).
  final String? copyValue;

  /// Bez elipse — vrijednost se prelama u više redaka (npr. opis plaćanja
  /// koji korisnik mora vidjeti cijeli da ga prepiše u bankovnu aplikaciju).
  final bool multiline;

  const PinkaCopyRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 110,
    this.copyValue,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style:
                  theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              overflow: multiline ? null : TextOverflow.ellipsis,
              softWrap: multiline,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 16),
            tooltip: l.commonCopy,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyValue ?? value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.pinkaCopiedLabel(label)),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Plain-text poruka s http(s) URL-ovima pretvorenim u sigurne vanjske linkove.
class PinkaLinkify extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const PinkaLinkify({super.key, required this.text, this.style});

  static final RegExp _url = RegExp(r'(https?:\/\/[^\s]+)');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = (style ?? theme.textTheme.bodySmall)?.copyWith(
      color: theme.colorScheme.tertiary,
      decoration: TextDecoration.underline,
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _url.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final url = m.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: linkStyle,
          recognizer: _LaunchTap(url),
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

/// Lagani tap recognizer koji otvara URL (bez dodatne ovisnosti o gesturama).
class _LaunchTap extends TapGestureRecognizer {
  _LaunchTap(String url) {
    onTap = () {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    };
  }
}

/// Otvori vanjski URL (explorer linkovi).
Future<void> pinkaLaunch(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
