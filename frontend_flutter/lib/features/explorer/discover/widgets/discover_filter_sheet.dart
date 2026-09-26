import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Filter bottom sheet for Discover screen.
///
/// Covers: Location, Time, Budget, Interests, Group, Accessibility,
/// Weather sensitivity, Local vs Tourist, Energy level.
class DiscoverFilterSheet extends StatefulWidget {
  const DiscoverFilterSheet({super.key});

  @override
  State<DiscoverFilterSheet> createState() => _DiscoverFilterSheetState();
}

class _DiscoverFilterSheetState extends State<DiscoverFilterSheet> {
  double _budgetMax = 1000;
  double _timeMax = 3;
  String _groupType = 'Any';
  final Set<String> _interests = {};
  bool _accessibleOnly = false;
  bool _localOnly = false;
  bool _openNow = false;
  String _energyLevel = 'Any';

  static const _interestOptions = [
    'Food', 'Art', 'Culture', 'History', 'Nature',
    'Heritage', 'Nightlife', 'Shopping', 'Wellness', 'Adventure',
  ];

  static const _groupOptions = ['Any', 'Solo', 'Couple', 'Family', 'Group'];
  static const _energyOptions = ['Any', 'Low', 'Medium', 'High'];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _resetAll,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Scrollable filters
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  // Budget
                  _FilterSection(
                    title: 'Budget',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Max budget',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600)),
                            Text(
                              _budgetMax >= 5000
                                  ? 'Any amount'
                                  : '₹${_budgetMax.round()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _budgetMax,
                          min: 0,
                          max: 5000,
                          divisions: 50,
                          onChanged: (v) => setState(() => _budgetMax = v),
                        ),
                      ],
                    ),
                  ),

                  // Time
                  _FilterSection(
                    title: 'Time available',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Max time',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600)),
                            Text(
                              _timeMax >= 8
                                  ? 'Full day'
                                  : '${_timeMax.round()} hr${_timeMax == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _timeMax,
                          min: 0.5,
                          max: 8,
                          divisions: 15,
                          onChanged: (v) => setState(() => _timeMax = v),
                        ),
                      ],
                    ),
                  ),

                  // Interests
                  _FilterSection(
                    title: 'Interests',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _interestOptions.map((interest) {
                        final selected = _interests.contains(interest);
                        return FilterChip(
                          label: Text(interest),
                          selected: selected,
                          onSelected: (v) => setState(() {
                            if (v) {
                              _interests.add(interest);
                            } else {
                              _interests.remove(interest);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ),

                  // Group type
                  _FilterSection(
                    title: 'Group',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _groupOptions.map((g) {
                        final selected = _groupType == g;
                        return ChoiceChip(
                          label: Text(g),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _groupType = g),
                        );
                      }).toList(),
                    ),
                  ),

                  // Energy level
                  _FilterSection(
                    title: 'Energy level',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _energyOptions.map((e) {
                        final selected = _energyLevel == e;
                        return ChoiceChip(
                          label: Text(e),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _energyLevel = e),
                        );
                      }).toList(),
                    ),
                  ),

                  // Toggles
                  _FilterSection(
                    title: 'Additional',
                    child: Column(
                      children: [
                        _Toggle(
                          label: 'Open now',
                          subtitle: 'Only show currently open',
                          value: _openNow,
                          onChanged: (v) => setState(() => _openNow = v),
                        ),
                        _Toggle(
                          label: 'Local gems only',
                          subtitle: 'Hidden spots locals love',
                          value: _localOnly,
                          onChanged: (v) => setState(() => _localOnly = v),
                        ),
                        _Toggle(
                          label: 'Accessible',
                          subtitle: 'Wheelchair & low-walking routes',
                          value: _accessibleOnly,
                          onChanged: (v) =>
                              setState(() => _accessibleOnly = v),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Apply button
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border(top: BorderSide(color: AppColors.border)),
                boxShadow: AppShadows.raised,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50)),
                  child: const Text('Apply filters'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetAll() {
    setState(() {
      _budgetMax = 1000;
      _timeMax = 3;
      _groupType = 'Any';
      _interests.clear();
      _accessibleOnly = false;
      _localOnly = false;
      _openNow = false;
      _energyLevel = 'Any';
    });
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 10),
        child,
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
