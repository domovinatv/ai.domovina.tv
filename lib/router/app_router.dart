import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../onboarding/moments/m4_handoff_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/channel/channel_screen.dart';
import '../screens/episode_screen.dart';
import '../screens/episode_simple_screen.dart';
import '../screens/legal/privacy_screen.dart';
import '../screens/legal/terms_screen.dart';

/// App router — go_router s NoTransitionPage za instant navigaciju.
/// Svaka ruta ima ValueKey da go_router zna rebuildat kad se mijenja path.
GoRouter createRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('home'),
          child: HomeScreen(),
        ),
      ),
      GoRoute(
        path: '/c/:slug',
        pageBuilder: (context, state) {
          final slug = state.pathParameters['slug']!;
          final channelId = slug.replaceAll('-', '_');
          return NoTransitionPage(
            key: ValueKey('channel-$slug'),
            child: ChannelScreen(channelId: channelId),
          );
        },
      ),
      GoRoute(
        path: '/v/:videoId',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          final t = state.uri.queryParameters['t'];
          final startAt = t != null ? int.tryParse(t) : null;
          return NoTransitionPage(
            key: ValueKey('video-$videoId-${startAt ?? 0}'),
            child: EpisodeScreen(
              youtubeId: videoId,
              startAtSeconds: startAt,
            ),
          );
        },
      ),
      // Path-based timestamp share — /v/<id>/t/<sec>
      // Path varijanta postoji da svaki clip ima vlastiti crawler cache entry
      // (Facebook/LinkedIn/WhatsApp normaliziraju query param verzije).
      GoRoute(
        path: '/v/:videoId/t/:seconds',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          final startAt = int.tryParse(state.pathParameters['seconds'] ?? '');
          return NoTransitionPage(
            key: ValueKey('video-$videoId-${startAt ?? 0}'),
            child: EpisodeScreen(
              youtubeId: videoId,
              startAtSeconds: startAt,
            ),
          );
        },
      ),
      // Mobile simplified view
      GoRoute(
        path: '/m/:videoId',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          return NoTransitionPage(
            key: ValueKey('mobile-$videoId'),
            child: EpisodeSimpleScreen(youtubeId: videoId),
          );
        },
      ),
      // M4 handoff — cross-device sign-in transfer
      GoRoute(
        path: '/handoff',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('handoff'),
          child: HandoffScreen(),
        ),
      ),
      GoRoute(
        path: '/handoff/:code',
        pageBuilder: (context, state) {
          final code = state.pathParameters['code'];
          return NoTransitionPage(
            key: ValueKey('handoff-$code'),
            child: HandoffScreen(prefilledCode: code),
          );
        },
      ),
      // Legalne stranice — placeholderi za Google OAuth consent screen.
      GoRoute(
        path: '/privacy',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('privacy'),
          child: PrivacyScreen(),
        ),
      ),
      GoRoute(
        path: '/terms',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('terms'),
          child: TermsScreen(),
        ),
      ),
      // Legacy format
      GoRoute(
        path: '/episode/:videoId',
        redirect: (context, state) =>
            '/v/${state.pathParameters['videoId']}',
      ),
    ],
    // ?v=ytId query param support (redirect to /v/ytId)
    redirect: (context, state) {
      final v = state.uri.queryParameters['v'];
      if (v != null && v.isNotEmpty && state.matchedLocation == '/') {
        return '/v/$v';
      }
      return null;
    },
    errorPageBuilder: (context, state) => const NoTransitionPage(
      key: ValueKey('error'),
      child: HomeScreen(),
    ),
  );
}
