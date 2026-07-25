/// Premium, brandirani UI blokovi za auth flow (sheet, dialozi, callback).
///
/// Sve koristi editorial design system (Playfair display + Inter UI, cream
/// papir, Croatian navy/crveni akcent). Cilj: ozbiljan, "papirnati" premium
/// dojam umjesto generičkih Material kontrola.
library;

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/typography.dart';

/// DOMOVINA "D" logo mark (hrvatska trikolora + AI graf). PNG (ne SVG) zbog
/// web release build gotcha-e.
class DomovinaLogoMark extends StatelessWidget {
  final double size;
  const DomovinaLogoMark({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/domovina_ai_logo_1024.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
    );
  }
}

/// Wordmark "DOMOVINA.ai" — Playfair 800, ".ai" u crvenom akcentu.
class DomovinaWordmark extends StatelessWidget {
  final double fontSize;
  const DomovinaWordmark({super.key, this.fontSize = 20});

  @override
  Widget build(BuildContext context) {
    final base = AppTypography.wordmarkStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: fontSize,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'DOMOVINA'),
          TextSpan(text: '.ai', style: TextStyle(color: AppTheme.croRed)),
        ],
      ),
    );
  }
}

/// Tanka hrvatska trikolora kao suptilan brand akcent (crveno/bijelo/navy).
class TricolorAccent extends StatelessWidget {
  final double width;
  final double height;
  const TricolorAccent({super.key, this.width = 44, this.height = 3});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        width: width,
        height: height,
        child: Row(
          children: [
            Expanded(child: ColoredBox(color: AppTheme.croRed)),
            const Expanded(child: ColoredBox(color: Colors.white)),
            Expanded(child: ColoredBox(color: AppTheme.croBlue)),
          ],
        ),
      ),
    );
  }
}

/// Brandirani header za auth sheet/dialoge: logo + wordmark + trikolor +
/// naslov (Playfair) + podnaslov.
class AuthBrandHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final double logoSize;

  /// [compact] izostavlja logo/wordmark/trikoloru — za pod-korake (e-mail,
  /// OTP) gdje otvorena tipkovnica pojede pola sheeta pa CTA ode van ekrana.
  final bool compact;

  const AuthBrandHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.logoSize = 56,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (!compact) ...[
          DomovinaLogoMark(size: logoSize),
          const SizedBox(height: 12),
          const DomovinaWordmark(fontSize: 18),
          const SizedBox(height: 10),
          const TricolorAccent(),
          const SizedBox(height: 18),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 23,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

/// "ili" separator s hairline linijama s obje strane.
class LabeledDivider extends StatelessWidget {
  final String? label;
  const LabeledDivider({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = label ?? AppLocalizations.of(context).authOr;
    final line = Expanded(
      child: Divider(
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

/// Premium provider tile. [primary] = istaknuti (navy filled, sjena, badge);
/// inače čista kartica s obrubom. [iconChild] je leading glyph (npr. Icon ili
/// stilizirano "G").
///
/// [loading] prikaže spinner umjesto trailing strelice/badgea (tile koji je
/// pokrenuo operaciju); [enabled]=false utiša i blokira tap (ostali tile-ovi
/// dok operacija traje).
class AuthProviderTile extends StatefulWidget {
  final Widget iconChild;
  final Color iconBg;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool primary;
  final String? badge;

  /// Boja badge pille (default crvena — PREPORUČENO; navy za ZADNJI PUT).
  final Color? badgeColor;
  final bool enabled;
  final bool loading;

  /// Semantics sidro za e2e (vidi docs/e2e-testing.md).
  final String? identifier;

  const AuthProviderTile({
    super.key,
    required this.iconChild,
    required this.iconBg,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.primary = false,
    this.badge,
    this.badgeColor,
    this.enabled = true,
    this.loading = false,
    this.identifier,
  });

  @override
  State<AuthProviderTile> createState() => _AuthProviderTileState();
}

class _AuthProviderTileState extends State<AuthProviderTile> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final primary = widget.primary;
    final interactive = widget.enabled && !widget.loading;
    // Tipkovnički fokus (Tab na webu) mora biti vidljiv jednako kao hover —
    // default InkWell focus overlay se na navy tile-u praktički ne vidi.
    final hover = (_hover || _focused) && interactive;

    final bg = primary
        ? AppTheme.croBlue
        : cs.surfaceContainerLowest;
    final fg = primary ? Colors.white : cs.onSurface;
    final subFg = primary
        ? Colors.white.withValues(alpha: 0.78)
        : cs.onSurfaceVariant;

    return Semantics(
      identifier: widget.identifier,
      child: MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        // Tile koji se vrti ostaje pun; ostali se utišaju dok traje operacija.
        opacity: widget.enabled || widget.loading ? 1 : 0.45,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: primary
              ? null
              : Border.all(
                  color: hover
                      ? cs.primary.withValues(alpha: 0.5)
                      : cs.outlineVariant.withValues(alpha: 0.7),
                  width: 1,
                ),
          boxShadow: primary
              ? [
                  BoxShadow(
                    color: AppTheme.croBlue.withValues(alpha: hover ? 0.34 : 0.24),
                    blurRadius: hover ? 22 : 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : (hover
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: interactive ? widget.onTap : null,
            onFocusChange: (f) => setState(() => _focused = f),
            focusColor: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.iconBg,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: widget.iconChild,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: fg,
                            fontSize: 15,
                          ),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: subFg,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.loading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(
                            primary ? Colors.white : cs.primary),
                      ),
                    )
                  else if (widget.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.badgeColor ?? AppTheme.croRed,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.badge!,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 13,
                      color: primary
                          ? Colors.white.withValues(alpha: 0.7)
                          : cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
      ),
    );
  }
}

/// Premium input dialog (e-mail / OTP kod) — brandiran header, cream kartica,
/// zaobljeni rubovi. Vraća upisani string (trimani) ili null na odustani.
Future<String?> showAuthInputDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String hint,
  required IconData icon,
  TextInputType keyboardType = TextInputType.text,
  int? maxLength,
  String? confirmLabel,
  Iterable<String>? autofillHints,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _AuthInputDialog(
      title: title,
      message: message,
      hint: hint,
      icon: icon,
      keyboardType: keyboardType,
      maxLength: maxLength,
      confirmLabel: confirmLabel,
      autofillHints: autofillHints,
    ),
  ).then((v) => (v == null || v.isEmpty) ? null : v);
}

class _AuthInputDialog extends StatefulWidget {
  final String title;
  final String message;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final int? maxLength;
  final String? confirmLabel;
  final Iterable<String>? autofillHints;

  const _AuthInputDialog({
    required this.title,
    required this.message,
    required this.hint,
    required this.icon,
    required this.keyboardType,
    required this.maxLength,
    required this.confirmLabel,
    required this.autofillHints,
  });

  @override
  State<_AuthInputDialog> createState() => _AuthInputDialogState();
}

class _AuthInputDialogState extends State<_AuthInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final maxLength = widget.maxLength;
    return Dialog(
      backgroundColor: cs.surface,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(widget.icon, color: cs.primary, size: 26),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontSize: 21),
            ),
            const SizedBox(height: 8),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: widget.keyboardType,
              autofillHints: widget.autofillHints,
              textInputAction: TextInputAction.done,
              textAlign:
                  maxLength != null ? TextAlign.center : TextAlign.start,
              maxLength: maxLength,
              style: maxLength != null
                  ? theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 24, letterSpacing: 8)
                  : null,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: widget.hint,
                counterText: '',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _submit,
              child: Text(widget.confirmLabel ?? l.commonConfirm),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                l.commonCancel,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
