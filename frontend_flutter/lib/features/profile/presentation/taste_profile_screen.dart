import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';

/// Phase 13: Taste Profile Screen
class TasteProfileScreen extends ConsumerStatefulWidget {
  const TasteProfileScreen({super.key});

  @override
  ConsumerState<TasteProfileScreen> createState() => _TasteProfileScreenState();
}

class _TasteProfileScreenState extends ConsumerState<TasteProfileScreen> {
  double _spontaneity = 65;
  double _crowdTolerance = 35;
  double _budgetSensitivity = 50;
  double _pace = 70;

  final Set<String> _favCategories = {
    'Architecture & Heritage',
    'Street Food & Cafes',
    'Hidden Gems',
    'Seafront Promenades',
  };

  final List<String> _allCategories = [
    'Architecture & Heritage',
    'Street Food & Cafes',
    'Hidden Gems',
    'Seafront Promenades',
    'Contemporary Art',
    'Local Markets & Bazaars',
    'Nightlife & Speakeasies',
    'Nature & Green Spaces',
  ];

  bool _vegOnly = false;
  bool _wheelchairAccess = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Taste Profile & DNA'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header Explanation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.12),
                  AppColors.violet.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.tune_rounded, color: AppColors.primary, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'LocalIQ uses your Taste DNA to dynamically filter and rank experiences that fit your style.',
                    style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Taste Sliders Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Travel Temperament',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 16),

                _SliderTile(
                  title: 'Spontaneity',
                  leftLabel: 'Planned Itinerary',
                  rightLabel: 'Pure Serendipity',
                  value: _spontaneity,
                  onChanged: (v) => setState(() => _spontaneity = v),
                ),
                const Divider(height: 24),

                _SliderTile(
                  title: 'Crowd Preference',
                  leftLabel: 'Quiet & Serene',
                  rightLabel: 'Bustling & Vibrant',
                  value: _crowdTolerance,
                  onChanged: (v) => setState(() => _crowdTolerance = v),
                ),
                const Divider(height: 24),

                _SliderTile(
                  title: 'Budget Style',
                  leftLabel: 'Budget-Savvy',
                  rightLabel: 'Comfort & Splurge',
                  value: _budgetSensitivity,
                  onChanged: (v) => setState(() => _budgetSensitivity = v),
                ),
                const Divider(height: 24),

                _SliderTile(
                  title: 'Daily Pace',
                  leftLabel: 'Gentle & Unhurried',
                  rightLabel: 'High-Energy Pack',
                  value: _pace,
                  onChanged: (v) => setState(() => _pace = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Favorite Categories
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Favorite Vibe & Themes',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Select what makes an outing memorable to you:',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allCategories.map((cat) {
                    final isSelected = _favCategories.contains(cat);
                    return FilterChip(
                      label: Text(cat),
                      selected: isSelected,
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surfaceSecondary,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _favCategories.add(cat);
                          } else {
                            _favCategories.remove(cat);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Dietary & Accessibility
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preferences & Accessibility',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Strictly Vegetarian / Vegan Options', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Highlight cafes and street stalls with dedicated veg kitchens', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  value: _vegOnly,
                  activeThumbColor: const Color(0xFF0E7C5A),
                  onChanged: (v) => setState(() => _vegOnly = v),
                ),
                const Divider(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Wheelchair & Step-Free Access', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Only surface venues with verified accessible ramps and lifts', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  value: _wheelchairAccess,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _wheelchairAccess = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Save Button
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✨ Taste DNA Saved! Recommendations recalibrated.'),
                  backgroundColor: AppColors.primary,
                ),
              );
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            child: const Text('Save & Update Feed', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.leftLabel,
    required this.rightLabel,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String leftLabel;
  final String rightLabel;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            Text('${value.round()}%', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 13)),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: 100,
          activeColor: AppColors.primary,
          inactiveColor: AppColors.primary.withValues(alpha: 0.15),
          onChanged: onChanged,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(leftLabel, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            Text(rightLabel, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ],
    );
  }
}
