import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../home/home_screen.dart';
import '../itinerary/itinerary_screen.dart';
import '../map/map_screen.dart';
import '../profile/profile_screen.dart';
import '../recommendations/recommendations_screen.dart';

/// Bottom-nav shell: Explore, Map, Itinerary, Profile.
///
/// Explore hosts Home and Results in an [IndexedStack] so the bottom bar stays
/// visible while moving between search and results (as in the reference).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  void _select(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
  }

  @override
  Widget build(BuildContext context) {
    final int badgeCount = context.select<AppState, int>(
      (AppState s) => s.itineraryStops.length,
    );

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const <Widget>[
          _ExploreHost(),
          MapScreen(),
          ItineraryScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE7E4F3))),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _select,
          destinations: <Widget>[
            const NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Explore',
            ),
            const NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Badge.count(
                count: badgeCount,
                isLabelVisible: badgeCount > 0,
                child: const Icon(Icons.route_outlined),
              ),
              selectedIcon: Badge.count(
                count: badgeCount,
                isLabelVisible: badgeCount > 0,
                child: const Icon(Icons.route_rounded),
              ),
              label: 'Itinerary',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps Home / Results in sync with [AppState.exploreIndex].
class _ExploreHost extends StatelessWidget {
  const _ExploreHost();

  @override
  Widget build(BuildContext context) {
    final int index = context.select<AppState, int>(
      (AppState s) => s.exploreIndex,
    );
    return IndexedStack(
      index: index,
      children: const <Widget>[HomeScreen(), RecommendationsScreen()],
    );
  }
}
