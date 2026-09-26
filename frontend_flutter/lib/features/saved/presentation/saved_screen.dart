import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../itinerary/application/itinerary_controller.dart';
import '../../recommendations/domain/recommendation.dart';
import '../../recommendations/presentation/widgets/recommendation_card.dart';
import '../../saved/application/saved_controller.dart';

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedRecommendationsProvider);
    final ids = ref.watch(savedControllerProvider).value ?? const <String>{};
    final width = MediaQuery.sizeOf(context).width;
    final gutter = Breakpoints.gutter(width);
    final columns = Breakpoints.recoColumns(width - gutter * 2);

    if (saved.isEmpty) {
      return PageBody(
        slivers: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Saved', style: Theme.of(context).textTheme.headlineMedium),
          ),
          AppEmptyState(
            icon: Icons.favorite_border_rounded,
            title: ids.isEmpty ? 'Nothing saved yet' : 'Refreshing your list…',
            message:
                'Save anything worth coming back to. Saved places keep their '
                'feasibility verdict live, so you will see immediately if one '
                'stops fitting your current window.',
            action: FilledButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.explore_rounded, size: 17),
              label: const Text('Browse experiences'),
            ),
          ),
        ],
      );
    }

    final feasible = saved.where((r) => r.tier == FeasibilityTier.feasible).length;
    final partial = saved.where((r) => r.tier == FeasibilityTier.partial).length;
    final inPlan = ref
            .watch(itineraryControllerProvider)
            .value
            ?.stops
            .length ??
        0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.maxContent),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Saved',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${saved.length} saved · $feasible still achievable · '
                              '$partial need a trade-off',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => context.go('/home'),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add more'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _Chip(
                        icon: Icons.favorite_rounded,
                        label: '${saved.length} saved',
                        tone: AppColors.danger,
                      ),
                      _Chip(
                        icon: Icons.verified_rounded,
                        label: '$feasible achievable now',
                        tone: AppColors.success,
                      ),
                      if (partial > 0)
                        _Chip(
                          icon: Icons.pending_actions_rounded,
                          label: '$partial with a trade-off',
                          tone: AppColors.warning,
                        ),
                      if (inPlan > 0)
                        _Chip(
                          icon: Icons.playlist_add_check_rounded,
                          label: '$inPlan in your plan',
                          tone: AppColors.blue,
                        ),
                      TextButton.icon(
                        onPressed: () async {
                          await ref.read(savedControllerProvider.notifier).clear();
                          if (!context.mounted) return;
                          showAppToast(
                            context,
                            'Cleared your saved list',
                            icon: Icons.delete_outline_rounded,
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          minimumSize: const Size(0, 34),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: const Text('Clear all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  CardGrid(
                    columns: columns,
                    children: [
                      for (final rec in saved) RecommendationCard(recommendation: rec),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.tone});

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: tone.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}
