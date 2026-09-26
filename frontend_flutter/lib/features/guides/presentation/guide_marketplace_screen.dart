import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/guide.dart';
import '../data/guide_repository.dart';
import '../data/local_guides.dart';

/// Phase 11: Guide Marketplace Screen
class GuideMarketplaceScreen extends ConsumerStatefulWidget {
  const GuideMarketplaceScreen({super.key});

  @override
  ConsumerState<GuideMarketplaceScreen> createState() => _GuideMarketplaceScreenState();
}

class _GuideMarketplaceScreenState extends ConsumerState<GuideMarketplaceScreen> {
  String? _selectedSpecialty;
  bool _availableNowOnly = false;
  String _searchQuery = '';

  final List<String> _specialties = const [
    'All',
    'Art & Heritage',
    'Food Trails',
    'Street Art',
    'Coastal Walk',
    'Nightlife',
  ];

  @override
  Widget build(BuildContext context) {
    final guides = ref.watch(allGuidesProvider).value ?? kLocalGuides;
    final filtered = guides.where((guide) {
      if (_availableNowOnly && !guide.isAvailableNow) return false;
      if (_selectedSpecialty != null && _selectedSpecialty != 'All') {
        if (!guide.specialties.contains(_selectedSpecialty)) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final match = guide.name.toLowerCase().contains(q) ||
            guide.preferredAreas.any((a) => a.toLowerCase().contains(q)) ||
            guide.specialties.any((s) => s.toLowerCase().contains(q));
        if (!match) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Local Guides Marketplace'),
      ),
      body: Column(
        children: [
          // ── Search & Filter header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by guide name, area, or specialty...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // ── Specialty Pills
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _specialties.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final sp = _specialties[i];
                final isSelected = (_selectedSpecialty == null && sp == 'All') ||
                    _selectedSpecialty == sp;
                return ChoiceChip(
                  label: Text(sp),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  onSelected: (_) {
                    setState(() => _selectedSpecialty = sp == 'All' ? null : sp);
                  },
                );
              },
            ),
          ),

          // ── Available Now switch
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Color(0xFF0E7C5A), size: 18),
                const SizedBox(width: 6),
                const Text(
                  'Available for instant booking today',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const Spacer(),
                Switch(
                  value: _availableNowOnly,
                  activeThumbColor: const Color(0xFF0E7C5A),
                  onChanged: (val) => setState(() => _availableNowOnly = val),
                ),
              ],
            ),
          ),

          // ── Guide List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                return _GuideCard(guide: filtered[i]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.guide});

  final Guide guide;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: NetworkImage(guide.photoUrl),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          guide.name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.verified_rounded, size: 16, color: AppColors.primary),
                        const Spacer(),
                        Text(
                          guide.rateLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: AppColors.star),
                        const SizedBox(width: 3),
                        Text(
                          guide.rating.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '(${guide.reviewLabel}) · ${guide.yearsExperience}y exp',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Languages: ${guide.languageLabel}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            guide.bio,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: guide.specialties.map((s) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(s, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (guide.isAvailableNow)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E7C5A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF0E7C5A)),
                      SizedBox(width: 4),
                      Text(
                        'Available Today',
                        style: TextStyle(
                          color: Color(0xFF0E7C5A),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () => _showBookingModal(context, guide),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Book Experience'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showBookingModal(BuildContext context, Guide guide) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Book with ${guide.name}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Rate: ${guide.rateLabel} · Response time ~${guide.responseTimeMinutes} mins',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text('Sample Itineraries Offered:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              for (final itin in guide.sampleItineraries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(itin, style: const TextStyle(fontSize: 12.5))),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Booking request sent to ${guide.name}! They will confirm shortly.'),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                },
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
                child: const Text('Confirm Booking Request'),
              ),
            ],
          ),
        );
      },
    );
  }
}
