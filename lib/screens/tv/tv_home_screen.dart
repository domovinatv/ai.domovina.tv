import 'package:flutter/material.dart';

import '../../main.dart' show log;

/// Faza 1 skeleton TV home screena.
///
/// Cilj ovog koraka: dokazati da TV detekcija, theme branching i D-pad fokus
/// rade end-to-end na pravom Android TV uredjaju (Philips 7303). Sadrzaj je
/// placeholder — pravi rail-ovi, hero featured, "Nastavi slusati" i kanali
/// dolaze u Fazi 2 (vidi plan u razgovoru).
///
/// Focus model: hero "POKRENI" gumb dobiva autofocus pri startu. D-pad UP
/// vodi na app bar (Pretraga), D-pad DOWN na placeholder rail. Sve interakcije
/// trenutno samo logiraju — nema navigacije.
class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  final _searchFocus = FocusNode(debugLabel: 'tv-appbar-search');
  final _heroPlayFocus = FocusNode(debugLabel: 'tv-hero-play');
  final List<FocusNode> _railFocuses = List.generate(
    6,
    (i) => FocusNode(debugLabel: 'tv-rail-card-$i'),
  );

  @override
  void initState() {
    super.initState();
    log('TvHomeScreen.init (Faza 1 skeleton)');
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _heroPlayFocus.dispose();
    for (final n in _railFocuses) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // EON SDSTB02 reportira density 320 → 960×540 dp na 1080p TV-u.
            // Philips MT5891 zna biti slican. Hero se skalira proporcionalno
            // visini ekrana da rail uvijek ima ~280 dp.
            final h = constraints.maxHeight;
            final heroHeight = (h * 0.45).clamp(220.0, 380.0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildAppBar(theme),
                _buildHero(theme, heroHeight),
                const SizedBox(height: 20),
                Expanded(child: _buildPlaceholderRail(theme)),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 24, 48, 8),
      child: Row(
        children: [
          Text(
            'DOMOVINA.ai',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          _TvFocusableButton(
            label: 'Pretraga',
            icon: Icons.search,
            focusNode: _searchFocus,
            variant: _ButtonVariant.subtle,
            onPressed: () => log('TvHomeScreen: pretraga (Faza 2.5)'),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(ThemeData theme, double heroHeight) {
    final compact = heroHeight < 300;
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 16, 48, 0),
      child: Container(
        height: heroHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.25),
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: EdgeInsets.all(compact ? 28 : 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'NAJBOLJI IZBOR',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.tertiary,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: compact ? 6 : 12),
            Text(
              'Android TV — Faza 1 skeleton',
              style: (compact
                      ? theme.textTheme.titleLarge
                      : theme.textTheme.headlineMedium)
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: compact ? 6 : 12),
            if (!compact)
              Text(
                'TV detekcija, focus model i theme branching su zive. '
                'Pravi hero (featured epizoda) dolazi u Fazi 2.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            SizedBox(height: compact ? 14 : 28),
            _TvFocusableButton(
              label: 'POKRENI',
              icon: Icons.play_arrow,
              focusNode: _heroPlayFocus,
              variant: _ButtonVariant.primary,
              autofocus: true,
              onPressed: () => log('TvHomeScreen: hero play (Faza 4)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderRail(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 3,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'NAJNOVIJE (PLACEHOLDER)',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _railFocuses.length,
              separatorBuilder: (_, _) => const SizedBox(width: 24),
              itemBuilder: (context, i) => _TvPlaceholderCard(
                index: i,
                focusNode: _railFocuses[i],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable focus widgets — bit ce promovirani u lib/screens/tv/widgets/ kad
// pocnu sluziti drugim TV screenovima (Channel, Episode, Search).
// ---------------------------------------------------------------------------

enum _ButtonVariant { primary, subtle }

class _TvFocusableButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final FocusNode focusNode;
  final _ButtonVariant variant;
  final bool autofocus;
  final VoidCallback onPressed;

  const _TvFocusableButton({
    required this.label,
    required this.icon,
    required this.focusNode,
    required this.variant,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  State<_TvFocusableButton> createState() => _TvFocusableButtonState();
}

class _TvFocusableButtonState extends State<_TvFocusableButton> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPrimary = widget.variant == _ButtonVariant.primary;
    final bg = isPrimary
        ? theme.colorScheme.tertiary
        : (_focused
            ? theme.colorScheme.primaryContainer
            : Colors.transparent);
    final fg = isPrimary
        ? theme.colorScheme.onTertiary
        : theme.colorScheme.onSurface;
    final ringColor = isPrimary
        ? theme.colorScheme.onSurface
        : theme.colorScheme.primary;

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: _focused && isPrimary ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: isPrimary ? 32 : 20,
            vertical: isPrimary ? 16 : 12,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? ringColor : Colors.transparent,
              width: 4,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: isPrimary ? 28 : 22,
                color: fg,
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: (isPrimary
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.titleMedium)
                    ?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  letterSpacing: isPrimary ? 1.2 : 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvPlaceholderCard extends StatefulWidget {
  final int index;
  final FocusNode focusNode;

  const _TvPlaceholderCard({required this.index, required this.focusNode});

  @override
  State<_TvPlaceholderCard> createState() => _TvPlaceholderCardState();
}

class _TvPlaceholderCardState extends State<_TvPlaceholderCard> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() => _focused = widget.focusNode.hasFocus);
      if (widget.focusNode.hasFocus) {
        // Auto-scroll card into view when focused via D-pad.
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            log('TvHomeScreen: card ${widget.index} activated');
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: _focused ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 320,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              width: 4,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'Card ${widget.index + 1}',
            style: theme.textTheme.titleLarge,
          ),
        ),
      ),
    );
  }
}
