import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/typography.dart';
import '../../widgets/account_chip.dart';

/// Slim sticky app bar za home screen.
///
/// Layout:
/// [Logo "DOMOVINA.ai"]  [Pretraži ⌘K placeholder]  [AccountChip]
///
/// Search trigger je placeholder za sada — modal overlay dolazi u Korak 9.
/// Klik vodi na isti search field u headeru ispod (scroll + focus).
class HomeAppBar extends StatelessWidget {
  /// Callback kad user klikne na search trigger. Privremeno scrolla na
  /// postojeći search input u headeru; kasnije će otvoriti search overlay.
  final VoidCallback? onSearchTap;

  const HomeAppBar({super.key, this.onSearchTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SliverAppBar(
      pinned: true,
      floating: false,
      snap: false,
      toolbarHeight: 64,
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0.5,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          return Row(
            children: [
              _Wordmark(isDark: isDark),
              if (!isMobile) ...[
                const SizedBox(width: 24),
                Expanded(
                  child: _SearchTrigger(
                    onTap: onSearchTap,
                    placeholder: 'Pretrazi kanale i epizode',
                  ),
                ),
                const SizedBox(width: 16),
              ] else ...[
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.search, size: 20),
                  tooltip: 'Pretrazi',
                  onPressed: onSearchTap,
                ),
                const SizedBox(width: 4),
              ],
              const AccountChip(),
            ],
          );
        },
      ),
    );
  }
}

/// Wordmark "DOMOVINA.ai" — Playfair serif za premium editorial vibe.
/// `.ai` sufiks je u croRed kao Croatian flag akcent.
class _Wordmark extends StatelessWidget {
  final bool isDark;

  const _Wordmark({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final baseColor = isDark ? Colors.white : AppTheme.croBlue;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'DOMOVINA',
            style: AppTypography.wordmarkStyle(color: baseColor, fontSize: 22),
          ),
          TextSpan(
            text: '.ai',
            style: AppTypography.wordmarkStyle(
                color: AppTheme.croRed, fontSize: 22),
          ),
        ],
      ),
    );
  }
}

/// Search trigger button — izgleda kao input field, ali otvara overlay.
class _SearchTrigger extends StatelessWidget {
  final VoidCallback? onTap;
  final String placeholder;

  const _SearchTrigger({required this.onTap, required this.placeholder});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 40,
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: theme.colorScheme.surfaceContainerLow,
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.search,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.7)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  placeholder,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // ⌘K placeholder hint — funkcionira tek u Korak 9.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '⌘K',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
