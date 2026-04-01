import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/episode_screen.dart';

/// App router — go_router s NoTransitionPage za instant navigaciju.
/// Vidi CLAUDE.md za poznate probleme s Navigator 1.0 (back animation jank).
GoRouter createRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: HomeScreen(),
        ),
      ),
      GoRoute(
        path: '/c/:slug',
        pageBuilder: (context, state) {
          final slug = state.pathParameters['slug']!;
          final channelId = slug.replaceAll('-', '_');
          return NoTransitionPage(
            child: HomeScreen(initialChannelId: channelId),
          );
        },
      ),
      GoRoute(
        path: '/v/:videoId',
        pageBuilder: (context, state) => NoTransitionPage(
          child: EpisodeScreen(
              youtubeId: state.pathParameters['videoId']!),
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
      child: HomeScreen(),
    ),
  );
}
