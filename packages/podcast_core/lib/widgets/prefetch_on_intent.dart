import 'package:flutter/widgets.dart';

import '../services/episode_prefetch.dart';

/// Javlja [EpisodePrefetch] čim korisnik pokaže namjeru otvoriti epizodu:
/// miš uđe na karticu (desktop) ili prst/klik krene dolje (prethodi `onTap`-u
/// za ~100–300 ms). Ne hvata geste — [Listener] i [MouseRegion] samo
/// promatraju, pa `InkWell` ispod radi kao prije.
class PrefetchOnIntent extends StatelessWidget {
  final String episodeId;
  final Widget child;

  const PrefetchOnIntent({
    super.key,
    required this.episodeId,
    required this.child,
  });

  void _fire() => EpisodePrefetch.instance.intent(episodeId);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _fire(),
      child: Listener(
        onPointerDown: (_) => _fire(),
        child: child,
      ),
    );
  }
}
