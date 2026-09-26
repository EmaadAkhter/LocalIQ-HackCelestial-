import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Mobile bottom navigation — warm editorial style.
class PrimaryNavigationBar extends StatelessWidget {
  const PrimaryNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const _items = <({String label, IconData icon, IconData active})>[
    (
      label: 'Explore',
      icon: Icons.explore_outlined,
      active: Icons.explore_rounded,
    ),
    (
      label: 'My Plan',
      icon: Icons.route_outlined,
      active: Icons.route_rounded,
    ),
    (
      label: 'Saved',
      icon: Icons.favorite_border_rounded,
      active: Icons.favorite_rounded,
    ),
    (
      label: 'More',
      icon: Icons.info_outline_rounded,
      active: Icons.info_rounded,
    ),
  ];

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
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavButton(
                    label: _items[i].label,
                    icon: _items[i].icon,
                    activeIcon: _items[i].active,
                    selected: currentIndex == i,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.navActive : AppColors.navInactive;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      splashColor: AppColors.primary.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.navActive.withValues(alpha: 0.10)
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
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
                fontFamily: 'DM Sans',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
