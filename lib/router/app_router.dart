import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/episode_screen.dart';
import '../screens/episode_simple_screen.dart';

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
            child: HomeScreen(initialChannelId: channelId),
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
