import 'package:flutter/material.dart';

/// Vizualni stilovi fokusa za TV widgete.
enum TvFocusStyle {
  /// Episode/channel kartice — 4px primary ring, scale 1.08.
  card,

  /// Primarni CTA (hero PLAY) — 4px onSurface ring, scale 1.06.
  primaryButton,

  /// App bar / sekundarni gumbi — primaryContainer bg, 4px primary ring.
  subtleButton,
}

/// Reusable focus-aware wrapper za TV widgete.
///
/// Daje 3 stvari koje svaki D-pad target treba:
/// 1. **Vizualni indikator fokusa** — animirani 4px ring + scale, ovisno o
///    [style]. Bez ovoga TV je neupotrebljiv s ~3m udaljenosti.
/// 2. **Auto-scroll u viewport** — kad D-pad fokus dođe na element izvan
///    vidljivog dijela rail-a ili scroll containera, `ensureVisible` ga gura
///    u centar (alignment: 0.5).
/// 3. **OK/Enter activation** — mapira `ActivateIntent` na [onActivate].
///
/// Children se renderiraju kroz [builder] callback koji prima `focused` flag
/// — child može opcionalno mijenjati boju/sjenu ovisno o fokusu.
class TvFocusable extends StatefulWidget {
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onActivate;
  final TvFocusStyle style;
  final BorderRadius borderRadius;
  /// Ako `false`, fokus ne skalira widget — koristi se za liste gdje horizontal
  /// "pop" izgleda lose (chapter rows, sidebar liste). Ring + glow + bg-promjena
  /// i dalje rade.
  final bool scaleOnFocus;
  final Widget Function(BuildContext context, bool focused) builder;

  const TvFocusable({
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.onActivate,
    this.style = TvFocusStyle.card,
    this.borderRadius = BorderRadius.zero,
    this.scaleOnFocus = true,
    required this.builder,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onChange);
  }

  @override
  void dispose() {
    _node.removeListener(_onChange);
    // Dispose samo ako smo sami kreirali node (caller-ov node je njegova briga).
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final hasFocus = _node.hasFocus;
    if (hasFocus != _focused) {
      setState(() => _focused = hasFocus);
    }
    if (hasFocus) {
      // ensureVisible no-op-a ako nema Scrollable ancestor-a (npr. hero PLAY
      // gumb na fiksnoj poziciji); inace gura kartice/gumbe u centar viewporta.
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  double get _scale {
    if (!_focused || !widget.scaleOnFocus) return 1.0;
    // Card scale 1.18 — Play Movies-style dramatic pop tako da je razlika
    // izmedju focused/unfocused jasna na 3m udaljenosti. Buttoni se manje
    // skaliraju jer su vec dovoljno istaknuti tertiary/onSurface bg-om.
    return widget.style == TvFocusStyle.card ? 1.18 : 1.05;
  }

  Color _ringColor(ColorScheme scheme) {
    // Card fokus = tertiary (croRed) jer primary (croBlue-derived) gotovo
    // nestaje na dark TV pozadini s 3m udaljenosti. Tertiary + glow daje
    // unmistakable "ovo je aktivno" signal koji se vidi s kauca.
    return switch (widget.style) {
      TvFocusStyle.card => scheme.tertiary,
      TvFocusStyle.primaryButton => scheme.onSurface,
      TvFocusStyle.subtleButton => scheme.tertiary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ringColor = _ringColor(theme.colorScheme);

    return FocusableActionDetector(
      focusNode: _node,
      autofocus: widget.autofocus,
      actions: {
        if (widget.onActivate != null)
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onActivate!();
              return null;
            },
          ),
      },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _focused ? ringColor : Colors.transparent,
              width: 5,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: ringColor.withValues(alpha: 0.55),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: widget.builder(context, _focused),
        ),
      ),
    );
  }
}
