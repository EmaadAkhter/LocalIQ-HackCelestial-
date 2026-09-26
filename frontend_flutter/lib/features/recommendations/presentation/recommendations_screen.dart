import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/context_strip.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../places/application/plan_providers.dart';
import '../../places/presentation/widgets/discovery_search.dart';
import 'widgets/recommendation_feed.dart';

/// Alias so the rail can read the active plan.
final itineraryForPlan = itineraryForPlanProvider;

/// Full-page ranking. Deep-linkable at /recommendations.
class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = Breakpoints.isDesktop(width);
    final gutter = Breakpoints.gutter(width);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Recommendations'),
        leading: const BackButton(),
        actions: [
          IconButton(
            tooltip: 'What-if lab',
            onPressed: () => context.push('/what-if'),
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Assistant',
            onPressed: () => context.push('/assistant'),
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bodyWidth = constraints.maxWidth - gutter * 2;
          final feedWidth = desktop ? bodyWidth - Breakpoints.sidebar - 16 : bodyWidth;
          final columns = Breakpoints.recoColumns(feedWidth);

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: Breakpoints.maxContent),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ranked for right now',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Every option is scored on fit to your window, budget, '
                      'group, access needs and the current conditions — not on '
                      'ratings alone.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    const ContextSummaryRow(),
                    const SizedBox(height: 18),
                    if (desktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 13,
                            child: RecommendationFeed(columns: columns),
                          ),
                          const SizedBox(width: 16),
                          const SizedBox(
                            width: Breakpoints.sidebar,
                            child: _Rail(),
                          ),
                        ],
                      )
                    else
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RecommendationFeed(columns: 1),
                          SizedBox(height: 24),
                          _Rail(),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Rail extends ConsumerWidget {
  const _Rail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AssistantEntryCard(),
        SizedBox(height: 14),
        _PlanSummaryCard(),
      ],
    );
  }
}

class _PlanSummaryCard extends ConsumerWidget {
  const _PlanSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itinerary = ref.watch(itineraryForPlan).value;
    final stops = itinerary?.stops ?? const [];
    final cost = itinerary?.totalCost ?? 0;
    final total = itinerary?.totalMinutes ?? 0;

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your plan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Stops',
                  value: '${stops.length}',
                  icon: Icons.place_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: 'Duration',
                  value: total == 0 ? '—' : '${total}m',
                  icon: Icons.schedule_rounded,
                  tone: AppColors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: 'Cost',
                  value: cost == 0 ? 'Free' : '₹$cost',
                  icon: Icons.payments_outlined,
                  tone: AppColors.violet,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/plan'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              icon: const Icon(Icons.route_rounded, size: 16),
              label: const Text('Open plan'),
            ),
          ),
        ],
      ),
    );
  }
}
