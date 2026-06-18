import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'home_feed.dart';
import 'hero_section.dart';

/// Hero **karusel** — umjesto jedne istaknute epizode prikazuje uži izbor
/// (do 5 kandidata iz [HomeFeed.pickFeaturedCarousel]) s auto-rotacijom,
/// swipe-om, strelicama (desktop) i dots indikatorom. Kontrolna traka ispod
/// kartice nosi "U ROTACIJI" badge + dots.
///
/// Auto-advance se pauzira na hover (desktop) i tijekom drag-a; svaka ručna
/// navigacija (strelica / dot / swipe) resetira tajmer. Ako je `picks` length
/// 1, renderira goli [HeroSection] bez ikakvog karusel-chrome-a.
class HeroCarousel extends StatefulWidget {
  final List<FeaturedPick> picks;
  final bool isMobile;
  final void Function(String videoId) onPlay;
  final VoidCallback onSave;

  const HeroCarousel({
    super.key,
    required this.picks,
    required this.isMobile,
    required this.onPlay,
    required this.onSave,
  });

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  static const _interval = Duration(seconds: 7);

  int _index = 0;
  bool _forward = true;
  bool _paused = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant HeroCarousel old) {
    super.didUpdateWidget(old);
    // Lista se može promijeniti dok channel cache dotjekava — clampaj index.
    if (_index >= widget.picks.length) {
      _index = 0;
    }
    if (old.picks.length != widget.picks.length) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.picks.length <= 1) return;
    _timer = Timer.periodic(_interval, (_) {
      if (!_paused && mounted) _go(1);
    });
  }

  void _go(int dir) {
    final n = widget.picks.length;
    if (n <= 1) return;
    setState(() {
      _forward = dir > 0;
      _index = (_index + dir) % n;
      if (_index < 0) _index += n;
    });
  }

  /// Ručna navigacija strelicom / swipe-om — pomak + reset tajmera.
  void _manual(int dir) {
    _go(dir);
    _startTimer();
  }

  void _jump(int i) {
    if (i == _index) return;
    setState(() {
      _forward = i > _index;
      _index = i;
    });
    _startTimer();
  }

  Widget _slide(FeaturedPick pick, {EdgeInsets? padding}) {
    return HeroSection(
      featured: pick,
      isMobile: widget.isMobile,
      onPlay: () => widget.onPlay(pick.video.video.id),
      onSave: widget.onSave,
      outerPadding: padding ?? const EdgeInsets.fromLTRB(16, 8, 16, 24),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.picks.isEmpty) return const SizedBox.shrink();
    if (widget.picks.length == 1) return _slide(widget.picks.first);

    // Stisni donji razmak hero-a — kontrolnu traku crtamo sami ispod.
    const slidePadding = EdgeInsets.fromLTRB(16, 8, 16, 4);

    final card = MouseRegion(
      onEnter: (_) => _paused = true,
      onExit: (_) => _paused = false,
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          final vx = d.primaryVelocity ?? 0;
          if (vx < -80) {
            _manual(1);
          } else if (vx > 80) {
            _manual(-1);
          }
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topCenter,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          ),
          transitionBuilder: (child, anim) {
            final begin =
                _forward ? const Offset(0.06, 0) : const Offset(-0.06, 0);
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(begin: begin, end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<int>(_index),
            child: _slide(widget.picks[_index], padding: slidePadding),
          ),
        ),
      ),
    );

    return Column(
      children: [
        Stack(
          children: [
            card,
            if (!widget.isMobile)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _ArrowButton(
                        icon: Icons.chevron_left,
                        onTap: () => _manual(-1),
                      ),
                      _ArrowButton(
                        icon: Icons.chevron_right,
                        onTap: () => _manual(1),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        _controlBar(theme),
      ],
    );
  }

  Widget _controlBar(ThemeData theme) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
      child: Row(
        children: [
          _RotationBadge(count: widget.picks.length),
          const Spacer(),
          // Dots — tappable; aktivni je izduženi.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.picks.length, (i) {
              final active = i == _index;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => _jump(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: active ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active
                          ? AppTheme.croBlue
                          : cs.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                      border: active
                          ? Border.fromBorderSide(
                              AppTheme.brandRim(theme.brightness))
                          : null,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// "U ROTACIJI" badge — signalizira da hero nije jedan fiksni izbor nego se
/// dnevno bira nekoliko najboljih epizoda koje se automatski izmjenjuju.
class _RotationBadge extends StatelessWidget {
  final int count;
  const _RotationBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message:
          'Dnevno biramo $count najboljih epizoda — automatski se izmjenjuju.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.croBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.fromBorderSide(AppTheme.brandRim(theme.brightness)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.autorenew, size: 12, color: cs.primary),
            const SizedBox(width: 5),
            Text(
              'U ROTACIJI',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                height: 1.0,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Okrugla strelica za desktop ručnu navigaciju karusela.
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 26, color: Colors.white),
        ),
      ),
    );
  }
}
