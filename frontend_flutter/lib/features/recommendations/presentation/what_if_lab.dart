import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../context/application/discovery_context_controller.dart';
import '../../places/presentation/widgets/constraint_panel.dart';
import '../../routing/presentation/localiq_map_view.dart';
import '../application/recommendation_controller.dart';
import '../domain/recommendation.dart';

/// What-if lab.
///
/// Every control writes straight into the discovery context, so the ranking,
/// the map, the counts and the plan all re-render together. This is the
/// clearest demonstration of the product's central idea.
class WhatIfLab extends ConsumerWidget {
  const WhatIfLab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    final counts = ref.watch(recommendationCountsProvider);
    final result = ref.watch(recommendationControllerProvider).value;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = Breakpoints.isDesktop(width);

    return PageBody(
      slivers: [
        const _Header(),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.lavender,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      size: 18,
                      color: AppColors.violet,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Change a variable, watch everything move',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                  Text(
                    '${counts.total} evaluated',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _CountPill(
                    label: '${counts.feasible} feasible',
                    color: AppColors.success,
                    onTap: () => context.go('/recommendations'),
                  ),
                  _CountPill(
                    label: '${counts.partial} partial',
                    color: AppColors.warning,
                    onTap: () => context.go('/recommendations'),
                  ),
                  _CountPill(
                    label: '${counts.blocked} blocked',
                    color: AppColors.danger,
                    onTap: () => context.go('/recommendations'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ImpactBar(
                feasible: counts.feasible,
                partial: counts.partial,
                blocked: counts.blocked,
              ),
            ],
          ),
        ),
        const ConstraintPanel(),
        const BiasSlider(),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading(
                title: 'Map preview',
                subtitle: 'Pins re-colour as the ranking changes',
                icon: Icons.map_outlined,
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final pins = <PlacePin>[];
                  if (result != null) {
                    for (final rec in result.byTier.take(8)) {
                      pins.add(
                        PlacePin(
                          id: rec.experience.id,
                          label: rec.experience.title,
                          position: (
                            lat: rec.place.centre.latitude,
                            lng: rec.place.centre.longitude,
                          ),
                          tone: switch (rec.tier) {
                            FeasibilityTier.feasible => 'feasible',
                            FeasibilityTier.partial => 'partial',
                            FeasibilityTier.notFeasible => 'blocked',
                          },
                        ),
                      );
                    }
                  }
                  return LocalIqMapView(
                    pins: pins,
                    userLocation: (
                      lat: discovery.centre.latitude,
                      lng: discovery.centre.longitude,
                    ),
                    height: desktop ? 320 : 220,
                  );
                },
              ),
              const SizedBox(height: 12),
              const MapLegend(),
            ],
          ),
        ),
        _TopTenPanel(),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What if', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Constraints are live. Nothing here is a saved search — move a slider '
          'and the engine re-evaluates every option against the new conditions.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.color,
    this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      onTap: onTap,
      color: color.withValues(alpha: 0.08),
      borderColor: color.withValues(alpha: 0.20),
      elevated: false,
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }
}

class _ImpactBar extends StatelessWidget {
  const _ImpactBar({
    required this.feasible,
    required this.partial,
    required this.blocked,
  });

  final int feasible;
  final int partial;
  final int blocked;

  @override
  Widget build(BuildContext context) {
    final total = (feasible + partial + blocked).clamp(1, 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: SizedBox(
            height: 10,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.medium,
              builder: (context, value, _) => Row(
                children: [
                  for (final segment in [
                    (count: feasible, color: AppColors.success),
                    (count: partial, color: AppColors.warning),
                    (count: blocked, color: AppColors.danger),
                  ])
                    if (segment.count > 0)
                      Expanded(
                        flex: segment.count,
                        child: Opacity(
                          opacity: value,
                          child: Container(color: segment.color),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Share of the catalogue you can complete right now: '
          '${((feasible / total) * 100).round()}%',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Live top-ten, so the effect of a change is immediately legible.
class _TopTenPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(recommendationControllerProvider);
    return result.when(
      loading: () => const AppPanel(
        child: Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      ),
      error: (error, _) => AppEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not rank options',
        message: '$error',
        action: FilledButton(
          onPressed: () =>
              ref.read(recommendationControllerProvider.notifier).refresh(),
          child: const Text('Retry'),
        ),
      ),
      data: (data) {
        final top = data.byTier.take(10).toList();
        return AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: 'Current order',
                subtitle: 'Ranked across all ${data.evaluatedCount} options',
                icon: Icons.leaderboard_rounded,
                trailing: TextButton(
                  onPressed: () => context.go('/recommendations'),
                  child: const Text('See all'),
                ),
              ),
              const SizedBox(height: 12),
              for (final rec in top)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: rec.tier.color,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '${rec.rank}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rec.experience.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            Text(
                              rec.tier == FeasibilityTier.notFeasible
                                  ? rec.primaryBlocker
                                  : rec.verdict,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: rec.tier.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      AppBadge(
                        label: rec.score.toStringAsFixed(0),
                        color: AppColors.textMuted,
                        dense: true,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
