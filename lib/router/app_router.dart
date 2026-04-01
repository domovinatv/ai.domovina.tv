import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/episode_screen.dart';

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
          return NoTransitionPage(
            key: ValueKey('video-$videoId'),
            child: EpisodeScreen(youtubeId: videoId),
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
