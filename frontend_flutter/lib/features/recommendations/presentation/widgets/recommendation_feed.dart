import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../context/application/discovery_context_controller.dart';
import '../../application/recommendation_controller.dart';
import '../../domain/recommendation.dart';
import 'recommendation_card.dart';

/// Local alias so the feed can read the active context without importing the
/// whole controller into its public surface.
final discoveryContextProviderForFeed = discoveryContextProvider;

enum FeedSort {
  recommended('Recommended'),
  nearest('Nearest'),
  cheapest('Cheapest'),
  quickest('Quickest'),
  gems('Local gems');

  const FeedSort(this.label);
  final String label;
}

/// The full ranked surface: counts, sort control, the feasible list, the
/// partial list and the blocked list, each with its own framing.
class RecommendationFeed extends ConsumerStatefulWidget {
  const RecommendationFeed({super.key, this.columns = 2, this.showHeader = true});

  final int columns;
  final bool showHeader;

  @override
  ConsumerState<RecommendationFeed> createState() => _RecommendationFeedState();
}

class _RecommendationFeedState extends ConsumerState<RecommendationFeed> {
  FeedSort _sort = FeedSort.recommended;
  bool _showPartial = true;
  bool _showBlocked = true;

  List<Recommendation> _apply(List<Recommendation> source) {
    final items = [...source];
    switch (_sort) {
      case FeedSort.nearest:
        items.sort(
          (a, b) => a.outboundTravel.minutes.compareTo(b.outboundTravel.minutes),
        );
      case FeedSort.cheapest:
        items.sort((a, b) => a.experience.typicalSpend.compareTo(b.experience.typicalSpend));
      case FeedSort.quickest:
        items.sort((a, b) => a.completableMinutes.compareTo(b.completableMinutes));
      case FeedSort.gems:
        items.sort((a, b) => b.experience.localScore.compareTo(a.experience.localScore));
      case FeedSort.recommended:
        break;
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recommendationControllerProvider);

    return async.when(
      loading: () => const _LoadingBlock(),
      error: (error, _) => AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load recommendations',
        message: '$error',
        action: FilledButton.icon(
          onPressed: () =>
              ref.read(recommendationControllerProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Retry'),
        ),
      ),
      data: (result) {
        final feasible = _apply(result.feasible);
        final partial = _apply(result.partial);
        final blocked = result.blocked;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showHeader) ...[
              _Header(
                total: result.evaluatedCount,
                feasible: result.feasibleCount,
                partial: result.partialCount,
                blocked: result.blockedCount,
                sort: _sort,
                onSort: (value) => setState(() => _sort = value),
              ),
              const SizedBox(height: 16),
            ],
            if (feasible.isEmpty && partial.isEmpty)
              const AppEmptyState(
                icon: Icons.filter_alt_off_rounded,
                title: 'Nothing clears your constraints',
                message:
                    'Every option currently fails at least one hard '
                    'constraint. Widen your time window or budget, or relax the '
                    'accessibility filter in the what-if lab.',
              )
            else ...[
              if (feasible.isNotEmpty) ...[
                _TierHeading(
                  tier: FeasibilityTier.feasible,
                  count: feasible.length,
                  subtitle: 'You can complete these end to end in your window',
                ),
                const SizedBox(height: 12),
                CardGrid(
                  columns: widget.columns,
                  children: [
                    for (final rec in feasible)
                      RecommendationCard(recommendation: rec),
                  ],
                ),
              ],
              if (partial.isNotEmpty) ...[
                const SizedBox(height: 26),
                _CollapsibleTierHeading(
                  tier: FeasibilityTier.partial,
                  count: partial.length,
                  subtitle: 'Doable with a trade-off — trim the visit or accept a caveat',
                  expanded: _showPartial,
                  onToggle: () => setState(() => _showPartial = !_showPartial),
                ),
                if (_showPartial) ...[
                  const SizedBox(height: 12),
                  CardGrid(
                    columns: widget.columns,
                    children: [
                      for (final rec in partial)
                        RecommendationCard(recommendation: rec),
                    ],
                  ),
                ],
              ],
            ],
            const SizedBox(height: 26),
            _CollapsibleTierHeading(
              tier: FeasibilityTier.notFeasible,
              count: blocked.length,
              subtitle: 'Still shown, with the exact reason each one fails',
              expanded: _showBlocked,
              onToggle: () => setState(() => _showBlocked = !_showBlocked),
            ),
            if (_showBlocked) ...[
              const SizedBox(height: 12),
              CardGrid(
                columns: widget.columns,
                children: [
                  for (final rec in blocked)
                    RecommendationCard(recommendation: rec),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
              ),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.total,
    required this.feasible,
    required this.partial,
    required this.blocked,
    required this.sort,
    required this.onSort,
  });

  final int total;
  final int feasible;
  final int partial;
  final int blocked;
  final FeedSort sort;
  final ValueChanged<FeedSort> onSort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProviderForFeed);

    return Column(
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
                    'What you can do right now',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$total options evaluated · $feasible achievable as-is · '
                    '$partial with a trade-off · $blocked out of reach',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppBadge(
              label: '$feasible / $total',
              color: feasible > 0 ? AppColors.success : AppColors.danger,
              icon: feasible > 0
                  ? Icons.verified_rounded
                  : Icons.error_outline_rounded,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final option in FeedSort.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SelectChip(
                    label: option.label,
                    compact: true,
                    tone: AppColors.primary,
                    selected: sort == option,
                    onTap: () => onSort(option),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Checked against ${discovery.timeLabel} · ${discovery.budgetLabel} · '
          '${discovery.groupType.label.toLowerCase()} · '
          '${discovery.accessibility.label.toLowerCase()}',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _TierHeading extends StatelessWidget {
  const _TierHeading({
    required this.tier,
    required this.count,
    required this.subtitle,
  });

  final FeasibilityTier tier;
  final int count;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: tier.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tier.color.withValues(alpha: 0.24)),
          ),
          child: Icon(tier.icon, size: 14, color: tier.color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${tier.label} · $count',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: tier.color,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CollapsibleTierHeading extends StatelessWidget {
  const _CollapsibleTierHeading({
    required this.tier,
    required this.count,
    required this.subtitle,
    required this.expanded,
    required this.onToggle,
  });

  final FeasibilityTier tier;
  final int count;
  final String subtitle;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: tier.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tier.color.withValues(alpha: 0.24)),
              ),
              child: Icon(tier.icon, size: 14, color: tier.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${tier.label} · $count',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: tier.color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(expanded ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      ),
    );
  }
}
