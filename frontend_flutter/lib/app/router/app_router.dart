import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/about/presentation/about_screen.dart';
import '../../features/assistant/presentation/assistant_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/itinerary/presentation/plan_screen.dart';
import '../../features/places/presentation/screens/explore_screen.dart';
import '../../features/places/presentation/screens/place_details_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/recommendations/presentation/recommendations_screen.dart';
import '../../features/recommendations/presentation/what_if_lab.dart';
import '../../features/saved/presentation/saved_screen.dart';
import '../screens/welcome_screen.dart';
import '../shell/app_shell.dart';

/// Route table. Kept free of widget imports beyond the screens themselves.
///
/// Note on `parentNavigatorKey`: every route here is a *top-level* route, so
/// they all render on the root navigator. Setting `parentNavigatorKey` to a
/// key that is not bound to a `ShellRoute` (or to [GoRouter.navigatorKey])
/// makes go_router throw a debug assertion while constructing the router, so
/// the auth and detail screens deliberately do not set it.
GoRouter createAppRouter() {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/welcome',
    routes: [
      // ---------------------------------------------------------- entry
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: WelcomeScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: LoginScreen()),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: SignupScreen()),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: ForgotPasswordScreen()),
      ),

      // ------------------------------------------------------- main shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ExploreScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/plan',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: PlanScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/saved',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: SavedScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/about',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: AboutScreen()),
              ),
            ],
          ),
        ],
      ),

      // ---------------------------------------------------- pushed screens
      GoRoute(
        path: '/recommendations',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: RecommendationsScreen()),
      ),
      GoRoute(
        path: '/what-if',
        builder: (context, state) => const WhatIfLab(),
      ),
      GoRoute(
        path: '/place/:id',
        pageBuilder: (context, state) => MaterialPage(
          key: state.pageKey,
          child: PlaceDetailsScreen(
            experienceId: state.pathParameters['id'] ?? '',
            placeId: state.uri.queryParameters['place'],
          ),
        ),
      ),
      GoRoute(
        path: '/assistant',
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: false,
          child: AssistantScreen(),
        ),
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (context, state) => const MaterialPage(child: ProfileScreen()),
      ),

      // ------------------------------------------------------ legacy paths
      GoRoute(path: '/', redirect: (context, state) => '/explore'),
      GoRoute(path: '/home', redirect: (context, state) => '/explore'),
      GoRoute(path: '/discover', redirect: (context, state) => '/explore'),
      GoRoute(path: '/map', redirect: (context, state) => '/explore'),
      GoRoute(path: '/itinerary', redirect: (context, state) => '/plan'),
      GoRoute(path: '/ai-chat', redirect: (context, state) => '/assistant'),
    ],
    errorBuilder: (context, state) => RouteErrorScreen(location: state.uri.toString()),
  );
}

class RouteErrorScreen extends StatelessWidget {
  const RouteErrorScreen({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.explore_off_rounded,
                size: 42,
                color: AppColors.violet,
              ),
              const SizedBox(height: 14),
              const Text(
                'That page does not exist',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
              ),
              const SizedBox(height: 6),
              Text(
                location,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => context.go('/explore'),
                child: const Text('Back to Explore'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
