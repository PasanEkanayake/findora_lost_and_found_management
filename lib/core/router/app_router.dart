import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_providers.dart';
import '../supabase/supabase_client.dart';
import '../widgets/main_shell.dart';
import '../widgets/tab_back_guard.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/signup_welcome_screen.dart';
import '../../features/home/item_feed_screen.dart';
import '../../features/matches/item_matches_screen.dart';
import '../../features/matches/matches_screen.dart';
import '../../features/chat/chat_list_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/contact/contact_chat_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/items/item_detail_screen.dart';
import '../../features/items/edit_item_screen.dart';
import '../../features/items/data/item_model.dart';
import '../../features/items/post_item_screen.dart';
import '../../features/profile/admin_reports_screen.dart';
import '../../features/profile/edit_profile_screen.dart';
import '../../features/profile/my_items_screen.dart';
import '../../features/profile/notification_settings_screen.dart';
import '../../features/profile/privacy_safety_screen.dart';
import '../../features/profile/help_support_screen.dart';

/// Bridges a Stream (Supabase's auth state changes) into the Listenable
/// that go_router's `refreshListenable` expects, so the router re-evaluates
/// its `redirect` callback every time someone signs in, signs out, or their
/// token refreshes — without every screen needing its own subscription.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Exposed as a provider so it can be watched/disposed the Riverpod way,
/// and so later phases can inject a fake router in tests if needed.
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: GoRouterRefreshStream(supabase.auth.onAuthStateChange),
    redirect: (context, state) {
      final session = supabase.auth.currentSession;
      final isLoggedIn = session != null;
      final location = state.matchedLocation;
      final isAuthRoute =
          location == '/login' || location == '/signup' || location == '/onboarding';
      final isWelcomeRoute = location == '/welcome';

      // Let the splash screen's own timer make the very first hop (it
      // reads currentSession itself) so the logo gets a moment on screen.
      // The redirect below takes over for every navigation after that,
      // including a session expiring mid-use.
      if (location == '/splash') return null;

      if (!isLoggedIn && !isAuthRoute) return '/login';

      if (isLoggedIn) {
        // See looksLikeFreshOAuthSignup's doc (auth_providers.dart) for
        // what this detects and why; signupWelcomeSeenProvider stops it
        // from re-triggering on every navigation for the rest of this
        // same signup, since the account's timestamps don't change just
        // because the person moved past the welcome screen.
        final isFreshGoogleSignup = looksLikeFreshOAuthSignup(session.user) &&
            !ref.read(signupWelcomeSeenProvider);

        if (isFreshGoogleSignup) return isWelcomeRoute ? null : '/welcome';
        if (isWelcomeRoute || isAuthRoute) return '/feed';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(path: '/welcome', builder: (context, state) => const SignupWelcomeScreen()),
      GoRoute(
        path: '/post-item',
        builder: (context, state) => const PostItemScreen(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => ChatScreen(args: state.extra as ChatScreenArgs),
      ),
      GoRoute(
        path: '/contact-chat',
        builder: (context, state) => ContactChatScreen(args: state.extra as ContactChatArgs),
      ),
      GoRoute(
        path: '/item/:id',
        builder: (context, state) => ItemDetailScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/edit-item',
        builder: (context, state) => EditItemScreen(item: state.extra as ItemModel),
      ),
      GoRoute(
        path: '/item/:id/matches',
        builder: (context, state) => ItemMatchesScreen(
          itemId: state.pathParameters['id']!,
          itemTitle: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/admin/reports',
        builder: (context, state) => const AdminReportsScreen(),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/profile/my-items',
        builder: (context, state) => const MyItemsScreen(),
      ),
      GoRoute(
        path: '/profile/notifications',
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/profile/privacy-safety',
        builder: (context, state) => const PrivacySafetyScreen(),
      ),
      GoRoute(
        path: '/profile/help',
        builder: (context, state) => const HelpSupportScreen(),
      ),

      // Bottom-nav tabs. Each branch keeps its own navigation stack, so
      // switching tabs and back preserves scroll position/state.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/feed',
                builder: (context, state) =>
                    const TabBackGuard(isHomeTab: true, child: ItemFeedScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/matches',
                builder: (context, state) =>
                    const TabBackGuard(isHomeTab: false, child: MatchesScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chats',
                builder: (context, state) =>
                    const TabBackGuard(isHomeTab: false, child: ChatListScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) =>
                    const TabBackGuard(isHomeTab: false, child: ProfileScreen()),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
