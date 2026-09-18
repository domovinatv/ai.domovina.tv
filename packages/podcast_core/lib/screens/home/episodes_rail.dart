import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../../theme/typography.dart';

/// Sekcija s eyebrow naslovom i horizontalnim scrollom kartica.
///
/// Naslov je all-caps eyebrow s tankom navy podcrticom — editorial signature.
class EpisodesRail extends StatefulWidget {
  final String eyebrow;
  final List<Widget> cards;
  final bool isMobile;
  final Color? eyebrowAccentColor;

  /// Opcionalna akcija desno od naslova ("Prikaži sve") — za railove koji su
  /// isječak dulje liste (npr. spremljene epizode → `/favorites`).
  final VoidCallback? onSeeAll;
  final String? seeAllLabel;

  const EpisodesRail({
    super.key,
    required this.eyebrow,
    required this.cards,
    required this.isMobile,
    this.eyebrowAccentColor,
    this.onSeeAll,
    this.seeAllLabel,
  });

  @override
  State<EpisodesRail> createState() => _EpisodesRailState();
}

class _EpisodesRailState extends State<EpisodesRail> {
  final _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollState);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollState);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollState() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final left = pos.pixels > 4;
    final right = pos.pixels < pos.maxScrollExtent - 4;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  void _scrollBy(double delta) {
    final pos = _scrollController.position;
    final target = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// Shift+mouse wheel → horizontalni scroll (standardni desktop pattern).
  /// Bez Shift-a propustamo event default-u (vertical scroll roditelja).
  void _onPointerSignal(PointerScrollEvent event) {
    if (!HardwareKeyboard.instance.isShiftPressed) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final target =
        (pos.pixels + event.scrollDelta.dy).clamp(0.0, pos.maxScrollExtent);
    _scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.eyebrowAccentColor ?? theme.colorScheme.primary;
    // Drag devices: touch (mobile swipe), trackpad (Mac 2-finger swipe),
    // stylus. NE mouse — mouse drag preko InkWell-iranih kartica je
    // nepouzdan (gesture arena bira tap umjesto drag-a kad je move < ~18px).
    // Mouse user ima Shift+wheel i scroll arrows.
    final dragBehavior = ScrollConfiguration.of(context).copyWith(
      dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      },
      scrollbars: false,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(width: 24, height: 2, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.eyebrow.toUpperCase(),
                    style:
                        AppTypography.eyebrowStyle(theme.colorScheme).copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.onSeeAll != null && widget.seeAllLabel != null)
                  TextButton(
                    onPressed: widget.onSeeAll,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      widget.seeAllLabel!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Visina rail-a se ravna po stvarnom sadrzaju kartica (IntrinsicHeight)
          // umjesto fiksne vrijednosti — fiksna je ostavljala velik prazan
          // prostor ispod nizih kartica (npr. "Nastavi slušati" nema podnaslov
          // ni datum pa je kraca od "Najnovije epizode").
          Stack(
            children: [
              Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _onPointerSignal(event);
                  }
                },
                child: ScrollConfiguration(
                  behavior: dragBehavior,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < widget.cards.length; i++) ...[
                            if (i > 0) const SizedBox(width: 12),
                            widget.cards[i],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Scroll arrows — samo na non-mobile (desktop pokazivac).
              // Positioned top/bottom 0 → centriran na intrinsicnu visinu rail-a.
              if (!widget.isMobile && _canScrollLeft)
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _ArrowButton(
                      icon: Icons.chevron_left,
                      onTap: () => _scrollBy(-360),
                    ),
                  ),
                ),
              if (!widget.isMobile && _canScrollRight)
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _ArrowButton(
                      icon: Icons.chevron_right,
                      onTap: () => _scrollBy(360),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: theme.colorScheme.surface,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon,
                size: 22, color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}
