import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/about/presentation/about_screen.dart';
import '../../features/assistant/presentation/companion_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/guide_login_screen.dart';
import '../../features/auth/presentation/screens/guide_signup_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/chat/domain/chat_thread.dart';
import '../../features/chat/presentation/chat_thread_screen.dart';
import '../../features/chat/presentation/inbox_screen.dart';
import '../../features/director/presentation/director_screen.dart';
import '../../features/driver/presentation/driver_trip_screen.dart';
import '../../features/driver/presentation/driver_trips_screen.dart';
import '../../features/explorer/discover/presentation/discover_screen.dart';
import '../../features/explorer/home/presentation/home_screen.dart';
import '../../features/guides/presentation/guide_dashboard_screen.dart';
import '../../features/guides/presentation/guide_marketplace_screen.dart';
import '../../features/guides/presentation/guide_onboarding_screen.dart';
import '../../features/itinerary/presentation/plan_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/places/presentation/screens/explore_screen.dart';
import '../../features/places/presentation/screens/place_details_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/taste_profile_screen.dart';
import '../../features/quests/presentation/quests_screen.dart';
import '../../features/recommendations/presentation/recommendations_screen.dart';
import '../../features/recommendations/presentation/what_if_lab.dart';
import '../../features/routing/presentation/map_screen.dart';
import '../../features/safety/presentation/safety_screen.dart';
import '../../features/saved/presentation/saved_screen.dart';
import '../../features/social/presentation/notifications_screen.dart';
import '../../features/social/presentation/people_screen.dart';
import '../../features/social/presentation/random_meetup_screen.dart';
import '../../features/wallet/presentation/wallet_screen.dart';
import '../screens/welcome_screen.dart';
import '../shell/app_shell.dart';

/// Complete Route Table supporting all LocalIQ features across Phase 2 - 17.
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
        path: '/role-selection',
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
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) =>
            const MaterialPage(child: OnboardingScreen()),
      ),
      GoRoute(
        path: '/guide-onboarding',
        pageBuilder: (context, state) =>
            const MaterialPage(child: GuideOnboardingScreen()),
      ),
      GoRoute(
        path: '/guide-login',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: GuideLoginScreen()),
      ),
      GoRoute(
        path: '/guide-signup',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: GuideSignupScreen()),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) =>
            const MaterialPage(child: NotificationsScreen()),
      ),

      // ------------------------------------------------------- main shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // Branch 0: Home — feed, quick actions, proactive suggestions.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ExplorerHomeScreen()),
              ),
            ],
          ),
          // Branch 1: Explore — places, search, filters.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DiscoverScreen(
                    initialQuery: state.uri.queryParameters['q'],
                  ),
                ),
              ),
            ],
          ),
          // Branch 2: Travel Buddy — agentic conversational companion.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/travel-buddy',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: CompanionScreen()),
              ),
            ],
          ),
          // Branch 3: Guides — discover and book local guides.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/guides',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: GuideMarketplaceScreen()),
              ),
            ],
          ),
          // Branch 4: Plan / Itinerary.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/plan',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: PlanScreen()),
              ),
            ],
          ),
          // Branch 5: Profile / Settings.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ProfileScreen()),
              ),
            ],
          ),
        ],
      ),

      // ---------------------------------------------------- pushed feature screens
      // Phase 6: Experience Details
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
      // Phase 8: Map
      GoRoute(
        path: '/map',
        pageBuilder: (context, state) =>
            const MaterialPage(child: MapScreen()),
      ),
      // Phase 10: Safety
      GoRoute(
        path: '/safety',
        pageBuilder: (context, state) =>
            const MaterialPage(child: SafetyScreen()),
      ),
      // Phase 12: Guide Workspace / App
      GoRoute(
        path: '/guide/dashboard',
        pageBuilder: (context, state) =>
            const MaterialPage(child: GuideDashboardScreen()),
      ),
      // Driver: trip list + live trip map (pickup -> stops -> drop)
      GoRoute(
        path: '/driver',
        pageBuilder: (context, state) =>
            const MaterialPage(child: DriverTripsScreen()),
      ),
      GoRoute(
        path: '/driver/trip/:id',
        pageBuilder: (context, state) => MaterialPage(
          key: state.pageKey,
          child: DriverTripScreen(
            bookingId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
      ),
      // Phase 13: Taste Profile
      GoRoute(
        path: '/taste-profile',
        pageBuilder: (context, state) =>
            const MaterialPage(child: TasteProfileScreen()),
      ),
      // Phase 15: Quests
      GoRoute(
        path: '/quests',
        pageBuilder: (context, state) =>
            const MaterialPage(child: QuestsScreen()),
      ),
      // Phase 16: Experience Wallet
      GoRoute(
        path: '/wallet',
        pageBuilder: (context, state) =>
            const MaterialPage(child: WalletScreen()),
      ),
      // Phase 17: AI Experience Director
      GoRoute(
        path: '/director',
        pageBuilder: (context, state) =>
            const MaterialPage(child: DirectorScreen()),
      ),

      // Additional routes
      GoRoute(
        path: '/saved',
        pageBuilder: (context, state) =>
            const MaterialPage(child: SavedScreen()),
      ),
      GoRoute(
        path: '/about',
        pageBuilder: (context, state) =>
            const MaterialPage(child: AboutScreen()),
      ),
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
        path: '/legacy-explore',
        pageBuilder: (context, state) =>
            const MaterialPage(child: ExploreScreen()),
      ),

      // Phase 16: Random Meetup — spontaneous, activity-driven connection.
      GoRoute(
        path: '/people',
        pageBuilder: (context, state) =>
            const MaterialPage(child: RandomMeetupScreen()),
      ),
      // Matched explorers + meetup invitations live behind Random Meetup.
      GoRoute(
        path: '/people/matches',
        pageBuilder: (context, state) =>
            const MaterialPage(child: PeopleScreen()),
      ),

      // Unified Chat & Messaging: Guide ↔ Explorer and Matched Explorers
      GoRoute(
        path: '/inbox',
        pageBuilder: (context, state) =>
            const MaterialPage(child: InboxScreen()),
      ),
      GoRoute(
        path: '/chat/:id',
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          final thread = state.extra as ChatThread?;
          return MaterialPage(
            child: ChatThreadScreen(threadId: id, initialThread: thread),
          );
        },
      ),

      // ------------------------------------------------------ redirects
      GoRoute(path: '/', redirect: (context, state) => '/home'),
      GoRoute(path: '/discover', redirect: (context, state) => '/explore'),
      GoRoute(path: '/itinerary', redirect: (context, state) => '/plan'),
      GoRoute(path: '/companion', redirect: (context, state) => '/travel-buddy'),
      GoRoute(path: '/assistant', redirect: (context, state) => '/travel-buddy'),
      GoRoute(path: '/ai-chat', redirect: (context, state) => '/travel-buddy'),
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
                color: AppColors.primary,
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
                onPressed: () => context.go('/home'),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
