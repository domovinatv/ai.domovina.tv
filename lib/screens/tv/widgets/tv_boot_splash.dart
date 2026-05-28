import 'package:flutter/material.dart';

/// Boot-phase loading widget za TV.
///
/// Renderira IDENTIČNU sliku kao Android native splash
/// (`assets/splash/splash_full_1.png` = Mt 10,26-28 KS Jeruzalemska Biblija)
/// + diskretni "Učitavanje…" progress overlay na dnu.
///
/// Cilj: **vizualni kontinuitet** kad native splash hand-off-a u Flutter.
/// Korisnik samo nastavi čitati Mt 10,26-28 (idealne duljine za ~10s
/// loading window) bez frame change-a — Android native splash i Flutter
/// boot splash izgledaju isto.
///
/// Razlikuje se od [TvLoadingTips] koji ima rotirajuće tips + random
/// verse — to je dobro za druge loading state-ove ali ne za boot, gdje
/// želimo frame continuity s native splash-om.
class TvBootSplash extends StatelessWidget {
  final Duration progressDuration;

  const TvBootSplash({
    super.key,
    this.progressDuration = const Duration(seconds: 10),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      // Fallback navy u slučaju da slika kasni — boja se poklapa s
      // gradientom u splash_full_1.png pa transition izgleda atomski.
      color: const Color(0xFF002F6C),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/splash/splash_full_1.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            // Bez frame-builder fade-a — želimo instant prikaz da ne bude
            // double-flash s native splash hand-off-om.
            gaplessPlayback: true,
          ),
          // Bottom overlay: gradient navy fade + Učitavanje + progress.
          // Gradient sakriva sliku original "AI-obrada katoličkih podcasta"
          // bottom tagline pa Flutter overlay zauzme tu zonu cleanly.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 160,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00001F4C),
                    Color(0xFF001F4C),
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(80, 32, 80, 32),
              alignment: Alignment.bottomCenter,
              child: _buildProgress(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(ThemeData theme) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: progressDuration,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Učitavanje…',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${(value * 100).round()}%',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFFF6B6B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 3,
                color: const Color(0xFFFF1F1F),
                backgroundColor: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ],
        );
      },
    );
  }
}
