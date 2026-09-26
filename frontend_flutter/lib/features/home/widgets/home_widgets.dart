import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/place.dart';

/// "LocalIQ" wordmark with a trailing overflow menu.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text.rich(
            const TextSpan(
              children: <InlineSpan>[
                TextSpan(text: 'Local'),
                TextSpan(
                  text: 'IQ',
                  style: TextStyle(color: AppColors.primary),
                ),
              ],
            ),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
        ),
        IconButton(
          onPressed: () => _showAbout(context),
          icon: const Icon(Icons.more_horiz_rounded),
          tooltip: 'More',
        ),
      ],
    );
  }

  void _showAbout(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SheetTitle(title: 'LocalIQ'),
              Text(
                'Discover Local Smarter — feasible Mumbai plans built around your '
                'time, budget and mood. Running on local mock data for now.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              SizedBox(height: Insets.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Natural-language search bar with a mic affordance.
class NaturalLanguageSearchField extends StatelessWidget {
  const NaturalLanguageSearchField({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'What would you like to do?',
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textSecondary,
          size: 21,
        ),
        suffixIcon: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: const Icon(
              Icons.mic_none_rounded,
              size: 19,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Current-location card.
class LocationCard extends StatelessWidget {
  const LocationCard({
    required this.location,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final String location;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: const Icon(
              Icons.my_location_rounded,
              size: 19,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Compact metric card (time / budget).
class StatCard extends StatelessWidget {
  const StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 15, color: AppColors.primary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Interest chip row with an "add" affordance.
class InterestSelector extends StatelessWidget {
  const InterestSelector({
    required this.selected,
    required this.onToggle,
    super.key,
  });

  final Set<PlaceCategory> selected;
  final ValueChanged<PlaceCategory> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionLabel('Interests'),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: <Widget>[
            for (final PlaceCategory category in PlaceCategory.values)
              _InterestChip(
                category: category,
                isSelected: selected.contains(category),
                onTap: () => onToggle(category),
              ),
          ],
        ),
      ],
    );
  }
}

class _InterestChip extends StatelessWidget {
  const _InterestChip({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final PlaceCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.lavender : AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                category.icon,
                size: 15,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                category.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? AppColors.primaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented group-type control.
class GroupTypeSelector extends StatelessWidget {
  const GroupTypeSelector({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final GroupType selected;
  final ValueChanged<GroupType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionLabel('Group Type'),
        const SizedBox(height: Insets.sm),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: <Widget>[
              for (final GroupType type in GroupType.values)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(type),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: type == selected
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(Radii.sm + 2),
                      ),
                      child: Text(
                        type.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: type == selected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Step-free / wheelchair switch.
class AccessibilityToggle extends StatelessWidget {
  const AccessibilityToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      onTap: () => onChanged(!value),
      padding: const EdgeInsets.fromLTRB(
        Insets.md,
        Insets.sm,
        Insets.sm,
        Insets.sm,
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.accessible_rounded,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: Insets.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Step-free access',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 1),
                Text(
                  'Filter to wheelchair-friendly places',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared building blocks
// ---------------------------------------------------------------------------

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Insets.md),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: Radii.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardRadius,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: Radii.cardRadius,
            border: Border.all(color: AppColors.divider),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
  }
}

/// Shared bottom-sheet title.
class SheetTitle extends StatelessWidget {
  const SheetTitle({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.page,
        0,
        Insets.page,
        Insets.md,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}
