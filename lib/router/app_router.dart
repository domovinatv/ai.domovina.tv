import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../onboarding/moments/m4_handoff_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/channel/channel_screen.dart';
import '../screens/episode_screen.dart';
import '../screens/episode_simple_screen.dart';
import '../screens/legal/privacy_screen.dart';
import '../screens/legal/terms_screen.dart';
import '../screens/auth/auth_callback_screen.dart';
import '../screens/auth/invite_screen.dart';
import '../screens/tv/tv_channel_screen.dart';
import '../screens/tv/tv_episode_screen.dart';
import '../screens/tv/tv_home_screen.dart';
import '../services/tv_mode.dart';

/// App router — go_router s NoTransitionPage za instant navigaciju.
/// Svaka ruta ima ValueKey da go_router zna rebuildat kad se mijenja path.
GoRouter createRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => NoTransitionPage(
          key: const ValueKey('home'),
          // Android TV (Leanback) dobiva vlastiti 10-foot UI home. Ostale
          // rute u Fazi 1 jos uvijek koriste desktop/mobile ekran — TV
          // varijante stizu u Fazi 2-4. Vidi lib/services/tv_mode.dart.
          child: TvMode.isTv ? const TvHomeScreen() : const HomeScreen(),
        ),
      ),
      GoRoute(
        path: '/c/:slug',
        pageBuilder: (context, state) {
          final slug = state.pathParameters['slug']!;
          final channelId = slug.replaceAll('-', '_');
          return NoTransitionPage(
            key: ValueKey('channel-$slug'),
            child: TvMode.isTv
                ? TvChannelScreen(channelId: channelId)
                : ChannelScreen(channelId: channelId),
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
            key: ValueKey('video-$videoId-${startAt ?? 0}-hr'),
            // Android TV (Leanback): standalone 10-foot UI. EN toggle nije jos
            // u TV varijanti (Faza 4.5), pa /v/<id>/en za sada renderira isti
            // TvEpisodeScreen (vidi tv ruta /en ispod).
            child: TvMode.isTv
                ? TvEpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  )
                : EpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  ),
          );
        },
      ),
      // Per-episode jezik — /v/<id>/en. Sufix umjesto ?lang=en jer social
      // crawleri (Facebook, LinkedIn, WhatsApp) cesto droppaju query parametre
      // pri normalizaciji URL-a, sto bi ulinkano resharanjima izgubilo
      // engleski OG title/description.
      GoRoute(
        path: '/v/:videoId/en',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          final t = state.uri.queryParameters['t'];
          final startAt = t != null ? int.tryParse(t) : null;
          return NoTransitionPage(
            key: ValueKey('video-$videoId-${startAt ?? 0}-en'),
            child: TvMode.isTv
                ? TvEpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  )
                : EpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                    initialLanguageEn: true,
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
            key: ValueKey('video-$videoId-${startAt ?? 0}-hr'),
            child: TvMode.isTv
                ? TvEpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  )
                : EpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  ),
          );
        },
      ),
      // Engleski + timestamp — /v/<id>/t/<sec>/en
      GoRoute(
        path: '/v/:videoId/t/:seconds/en',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          final startAt = int.tryParse(state.pathParameters['seconds'] ?? '');
          return NoTransitionPage(
            key: ValueKey('video-$videoId-${startAt ?? 0}-en'),
            child: TvMode.isTv
                ? TvEpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  )
                : EpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                    initialLanguageEn: true,
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
            key: ValueKey('mobile-$videoId-hr'),
            child: EpisodeSimpleScreen(youtubeId: videoId),
          );
        },
      ),
      GoRoute(
        path: '/m/:videoId/en',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          return NoTransitionPage(
            key: ValueKey('mobile-$videoId-en'),
            child: EpisodeSimpleScreen(
              youtubeId: videoId,
              initialLanguageEn: true,
            ),
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
      GoRoute(
        path: '/auth/callback',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('auth_callback'),
          child: AuthCallbackScreen(),
        ),
      ),
      GoRoute(
        path: '/login-callback',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('login_callback'),
          child: AuthCallbackScreen(),
        ),
      ),
      GoRoute(
        path: '/invite',
        pageBuilder: (context, state) {
          final token = state.uri.queryParameters['token'];
          return NoTransitionPage(
            key: ValueKey('invite'),
            child: InviteScreen(token: token),
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
    errorPageBuilder: (context, state) => NoTransitionPage(
      key: const ValueKey('error'),
      child: TvMode.isTv ? const TvHomeScreen() : const HomeScreen(),
    ),
  );
}
