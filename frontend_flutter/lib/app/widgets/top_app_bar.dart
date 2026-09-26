import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/providers.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../features/auth/domain/user.dart';
import '../../features/context/application/discovery_context_controller.dart';
import '../../features/context/domain/context_models.dart';
import '../../features/saved/application/saved_controller.dart';
import '../../shared/widgets/ui_kit.dart';
import 'brand.dart';

class LocalIqAppBar extends ConsumerWidget {
  const LocalIqAppBar({super.key, required this.currentIndex});

  final int currentIndex;

  static const navItems = <({String label, String path, IconData icon})>[
    (label: 'Explore', path: '/explore', icon: Icons.explore_rounded),
    (label: 'My Plan', path: '/plan', icon: Icons.route_rounded),
    (label: 'Saved', path: '/saved', icon: Icons.favorite_rounded),
    (label: 'About', path: '/about', icon: Icons.info_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;

    // Progressive disclosure keeps the row legible at every width.
    final showTagline = width >= 1220;
    final showLocation = width >= 1060;
    final showAssistant = width >= 900;
    final compact = width < 1000;

    return Material(
      color: AppColors.surfaceLifted,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 24,
              vertical: 11,
            ),
            child: compact
                ? _CompactBar(
                    currentIndex: currentIndex,
                    showLocation: width >= 380,
                  )
                : _WideBar(
                    currentIndex: currentIndex,
                    showTagline: showTagline,
                    showLocation: showLocation,
                    showAssistant: showAssistant,
                  ),
          ),
        ),
      ),
    );
  }
}

class _WideBar extends ConsumerWidget {
  const _WideBar({
    required this.currentIndex,
    required this.showTagline,
    required this.showLocation,
    required this.showAssistant,
  });

  final int currentIndex;
  final bool showTagline;
  final bool showLocation;
  final bool showAssistant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        const BrandLockup(height: 32, showTagline: false),
        if (showTagline) ...[
          const SizedBox(width: 14),
          const BrandWordmark(),
        ],
        const SizedBox(width: 22),
        for (final item in LocalIqAppBar.navItems)
          _NavItem(
            label: item.label,
            selected: currentIndex ==
                LocalIqAppBar.navItems.indexWhere((e) => e.path == item.path),
            onTap: () => context.go(item.path),
          ),
        const Spacer(),
        if (showAssistant)
          TextButton.icon(
            onPressed: () => context.push('/assistant'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Ask LocalIQ'),
          ),
        if (showLocation) ...[
          const SizedBox(width: 10),
          const Flexible(child: LocationSelector()),
        ],
        const SizedBox(width: 10),
        const UserAvatarButton(),
      ],
    );
  }
}

class _CompactBar extends ConsumerWidget {
  const _CompactBar({required this.currentIndex, required this.showLocation});

  final int currentIndex;
  final bool showLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        const BrandLockup(height: 28, showTagline: false),
        const SizedBox(width: 9),
        const Flexible(
          child: Text(
            'LocalIQ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: -0.3,
              color: AppColors.primary,
            ),
          ),
        ),
        const Spacer(),
        if (showLocation) const Flexible(child: LocationSelector(compact: true)),
        const SizedBox(width: 8),
        const UserAvatarButton(),
      ],
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primarySurface
                : _hovered
                    ? AppColors.surfaceSecondary
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14,
                  color: active ? AppColors.primary : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: AppMotion.fast,
                height: 2.5,
                width: active ? 22 : 0,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Location picker. Writes straight into the discovery context so the map,
/// ranking and plan all follow.
class LocationSelector extends ConsumerWidget {
  const LocationSelector({super.key, this.compact = false});

  final bool compact;

  /// Curated starting points. A production build resolves these from
  /// geolocation + a places search.
  static const locations = <({String label, String short, double lat, double lng})>[
    (label: 'Fort, South Mumbai', short: 'Fort', lat: 18.9322, lng: 72.8316),
    (label: 'Colaba, Mumbai', short: 'Colaba', lat: 18.9217, lng: 72.8328),
    (label: 'Bandra West, Mumbai', short: 'Bandra', lat: 19.0423, lng: 72.8184),
    (label: 'Worli, Mumbai', short: 'Worli', lat: 19.0089, lng: 72.8156),
    (label: 'Byculla, Mumbai', short: 'Byculla', lat: 18.9790, lng: 72.8346),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final context_ = ref.watch(discoveryContextProvider);
    final controller = ref.read(discoveryContextProvider.notifier);

    return PopupMenuButton<int>(
      tooltip: 'Change your starting point',
      position: PopupMenuPosition.under,
      onSelected: (index) {
        final place = locations[index];
        controller.setLocation(
          place.label,
          GeoPoint(latitude: place.lat, longitude: place.lng),
        );
        showAppToast(context, 'Starting from ${place.label}', icon: Icons.location_on_rounded);
      },
      itemBuilder: (context) => [
        for (var i = 0; i < locations.length; i++)
          PopupMenuItem(
            value: i,
            height: 44,
            child: Row(
              children: [
                Icon(
                  i == locations.indexWhere((e) => e.label == context_.locationLabel)
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: i == locations.indexWhere((e) => e.label == context_.locationLabel)
                      ? AppColors.violet
                      : AppColors.borderStrong,
                ),
                const SizedBox(width: 10),
                Text(
                  locations[i].label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 11,
          vertical: compact ? 6 : 7,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_on_rounded,
              size: 15,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                compact
                    ? (locations
                            .firstWhere(
                              (e) => e.label == context_.locationLabel,
                              orElse: () => locations.first,
                            )
                            .short)
                    : context_.locationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

class UserAvatarButton extends ConsumerWidget {
  const UserAvatarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final savedCount = ref.watch(savedCountProvider);
    final initials = user?.initials ?? 'L';
    final name = user?.displayName ?? 'Guest';

    return Tooltip(
      message: user == null
          ? 'Guest session · $savedCount saved'
          : '${user.tier.label} · $name',
      child: InkWell(
        onTap: () => context.push('/profile'),
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.15),
                AppColors.primaryDark.withValues(alpha: 0.12),
              ],
            ),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
          ),
          child: Text(
            initials,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small environment/source indicator. Honest about where data comes from.
class DataSourceChip extends ConsumerWidget {
  const DataSourceChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteDataEnabledProvider);
    final env = ref.watch(environmentProvider);
    return Tooltip(
      message: remote
          ? 'Live data from ${env.apiBaseUrl}'
          : 'Using the bundled catalogue. Set LOCALIQ_API_BASE_URL to connect '
              'a backend.',
      child: AppBadge(
        label: remote ? 'LIVE' : 'LOCAL DATA',
        icon: remote ? Icons.cloud_done_rounded : Icons.storage_rounded,
        color: remote ? AppColors.success : AppColors.textMuted,
        dense: true,
      ),
    );
  }
}
