import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// Explorer-role app shell with the 6-tab bottom navigation.
///
/// Tabs: Home | Explore | Travel Buddy | Guides | Plan | Profile
class ExplorerShell extends StatelessWidget {
  const ExplorerShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = <({String label, IconData icon, IconData active})>[
    (
      label: 'Home',
      icon: Icons.home_outlined,
      active: Icons.home_rounded,
    ),
    (
      label: 'Explore',
      icon: Icons.explore_outlined,
      active: Icons.explore_rounded,
    ),
    (
      label: 'Buddy',
      icon: Icons.auto_awesome_outlined,
      active: Icons.auto_awesome_rounded,
    ),
    (
      label: 'Guides',
      icon: Icons.person_pin_circle_outlined,
      active: Icons.person_pin_circle_rounded,
    ),
    (
      label: 'Plan',
      icon: Icons.route_outlined,
      active: Icons.route_rounded,
    ),
    (
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      active: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: navigationShell,
      bottomNavigationBar: _ExplorerNav(
        currentIndex: navigationShell.currentIndex,
        onSelect: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

class _ExplorerNav extends StatelessWidget {
  const _ExplorerNav({
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.navBar,
        border: Border(top: BorderSide(color: AppColors.navBarDivider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              for (var i = 0; i < ExplorerShell._items.length; i++)
                Expanded(
                  child: _NavItem(
                    label: ExplorerShell._items[i].label,
                    icon: ExplorerShell._items[i].icon,
                    activeIcon: ExplorerShell._items[i].active,
                    selected: currentIndex == i,
                    onTap: () => onSelect(i),
                    accent: AppColors.navActive,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Guide-role app shell with the 5-tab bottom navigation.
///
/// Tabs: Dashboard | Experiences | Bookings | Availability | Profile
class GuideShell extends StatelessWidget {
  const GuideShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = <({String label, IconData icon, IconData active})>[
    (
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      active: Icons.dashboard_rounded,
    ),
    (
      label: 'Experiences',
      icon: Icons.category_outlined,
      active: Icons.category_rounded,
    ),
    (
      label: 'Bookings',
      icon: Icons.calendar_today_outlined,
      active: Icons.calendar_today_rounded,
    ),
    (
      label: 'Availability',
      icon: Icons.schedule_outlined,
      active: Icons.schedule_rounded,
    ),
    (
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      active: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: navigationShell,
      bottomNavigationBar: _GuideNav(
        currentIndex: navigationShell.currentIndex,
        onSelect: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

class _GuideNav extends StatelessWidget {
  const _GuideNav({
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.navBar,
        border: Border(top: BorderSide(color: AppColors.navBarDivider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              for (var i = 0; i < GuideShell._items.length; i++)
                Expanded(
                  child: _NavItem(
                    label: GuideShell._items[i].label,
                    icon: GuideShell._items[i].icon,
                    activeIcon: GuideShell._items[i].active,
                    selected: currentIndex == i,
                    onTap: () => onSelect(i),
                    // Guide tab uses the primary warm terracotta
                    accent: AppColors.navActive,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : AppColors.navInactive;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      splashColor: AppColors.primary.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Icon(
                selected ? activeIcon : icon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: AppMotion.fast,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
                fontFamily: 'DM Sans',
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
