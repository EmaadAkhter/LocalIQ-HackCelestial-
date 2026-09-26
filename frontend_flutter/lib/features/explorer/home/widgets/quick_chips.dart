import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';

/// Horizontal quick-filter chips below the search field.
///
/// Each chip represents a common discovery constraint.
class QuickChips extends StatefulWidget {
  const QuickChips({super.key});

  @override
  State<QuickChips> createState() => _QuickChipsState();
}

class _QuickChipsState extends State<QuickChips> {
  final Set<int> _selected = {};

  static const _chips = [
    _Chip(label: '2 hours', icon: Icons.schedule_outlined),
    _Chip(label: 'Under ₹1000', icon: Icons.payments_outlined),
    _Chip(label: 'Indoor', icon: Icons.roofing_outlined),
    _Chip(label: 'Food', icon: Icons.restaurant_outlined),
    _Chip(label: 'Culture', icon: Icons.museum_outlined),
    _Chip(label: 'Family', icon: Icons.family_restroom_outlined),
    _Chip(label: 'Solo', icon: Icons.person_outlined),
    _Chip(label: 'Local Gems', icon: Icons.diamond_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final chip = _chips[i];
          final selected = _selected.contains(i);
          return _ChipButton(
            label: chip.label,
            icon: chip.icon,
            selected: selected,
            onTap: () {
              setState(() {
                if (selected) {
                  _selected.remove(i);
                } else {
                  _selected.add(i);
                }
              });
              // Push to discover with the selected filter
              if (!selected) {
                context.push('/explore?q=${chip.label}');
              }
            },
          );
        },
      ),
    );
  }
}

class _Chip {
  const _Chip({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
          boxShadow: selected ? null : AppShadows.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
