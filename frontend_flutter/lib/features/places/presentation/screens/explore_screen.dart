import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../context/application/discovery_context_controller.dart';
import '../../../itinerary/application/itinerary_controller.dart';
import '../../../itinerary/domain/itinerary.dart';
import '../../../recommendations/application/recommendation_controller.dart';
import '../../../recommendations/presentation/widgets/recommendation_feed.dart';
import '../widgets/constraint_panel.dart';
import '../widgets/discovery_rails.dart';
import '../widgets/discovery_search.dart';

class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = Breakpoints.isDesktop(width);
    final gutter = Breakpoints.gutter(width);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bodyWidth = constraints.maxWidth - gutter * 2;
        final sidebarWidth = Breakpoints.sidebar;
        final feedWidth = desktop ? bodyWidth - sidebarWidth - 16 : bodyWidth;
        final columns = Breakpoints.recoColumns(feedWidth);

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.maxContent),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        FadeSlideIn(child: DiscoverySearch()),
                        SizedBox(height: 16),
                        FadeSlideIn(
                          delay: Duration(milliseconds: 60),
                          child: ScenarioRow(),
                        ),
                        SizedBox(height: 16),
                        FadeSlideIn(
                          delay: Duration(milliseconds: 110),
                          child: ConstraintPanel(),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, 22, gutter, 0),
                  sliver: SliverToBoxAdapter(
                    child: FadeSlideIn(
                      delay: const Duration(milliseconds: 150),
                      child: const _DiscoveryBlock(),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 0),
                  sliver: SliverToBoxAdapter(
                    child: desktop
                        ? _DesktopSplit(columns: columns)
                        : _StackedLayout(columns: columns),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, 26, gutter, 40),
                  sliver: const SliverToBoxAdapter(child: _ExploreFooter()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DiscoveryBlock extends ConsumerWidget {
  const _DiscoveryBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    final places = ref.watch(allPlacesProvider).value ?? const [];
    final width = MediaQuery.sizeOf(context).width;
    final twoUp = width >= 1060;

    if (places.isEmpty) {
      return const AppPanel(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final sorted = [...places]
      ..sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
    final popular = sorted.take(10).toList();
    final gems = [
      ...places.where((p) => p.localFavourite),
    ]..sort((a, b) => b.rating.compareTo(a.rating));
    final localGems = gems.take(10).toList();

    final rails = [
      DiscoveryRail(
        title: 'Popular nearby',
        subtitle: 'Highest footfall within ${discovery.locationLabel}',
        places: popular,
        icon: Icons.local_fire_department_outlined,
        badgeLabel: 'MOST VISITED',
      ),
      DiscoveryRail(
        title: 'Local gems',
        subtitle: 'Locals rate highly, visitors rarely find',
        places: localGems,
        icon: Icons.diamond_outlined,
        badgeLabel: 'UNDER THE RADAR',
      ),
    ];

    final map = MapPreviewPanel(
      height: width < 700 ? 210 : 250,
      pinLimit: 6,
    );
    const assistant = AssistantEntryCard();

    if (twoUp) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  rails[0],
                  const SizedBox(height: 22),
                  rails[1],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  map,
                  const SizedBox(height: 16),
                  assistant,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        rails[0],
        const SizedBox(height: 22),
        rails[1],
        const SizedBox(height: 22),
        map,
        const SizedBox(height: 16),
        assistant,
      ],
    );
  }
}

class _DesktopSplit extends StatelessWidget {
  const _DesktopSplit({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 13,
          child: RecommendationFeed(columns: columns),
        ),
        const SizedBox(width: 16),
        const SizedBox(
          width: Breakpoints.sidebar,
          child: _Sidebar(),
        ),
      ],
    );
  }
}

class _StackedLayout extends StatelessWidget {
  const _StackedLayout({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RecommendationFeed(columns: columns),
        const SizedBox(height: 24),
        const _Sidebar(),
      ],
    );
  }
}

/// Desktop rail: map, what-if entry and the live plan.
class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MapPreviewPanel(height: 240, pinLimit: 5),
        const SizedBox(height: 14),
        const _WhatIfLauncher(),
        const SizedBox(height: 14),
        const _MiniPlanCard(),
      ],
    );
  }
}

class _WhatIfLauncher extends ConsumerWidget {
  const _WhatIfLauncher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(recommendationCountsProvider);
    final total = (counts.feasible + counts.partial + counts.blocked).clamp(1, 1000);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.lavender,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: AppColors.violet,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'What if plans change?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Adjust anything — the ranking updates instantly.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: counts.feasible / total),
              duration: AppMotion.medium,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: AppColors.danger.withValues(alpha: 0.16),
                valueColor: const AlwaysStoppedAnimation(AppColors.success),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${counts.feasible} achievable · ${counts.partial} partial · '
            '${counts.blocked} blocked',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/what-if'),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Open what-if lab'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPlanCard extends ConsumerWidget {
  const _MiniPlanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itinerary = ref.watch(itineraryControllerProvider).value;
    final discovery = ref.watch(discoveryContextProvider);
    final stops = itinerary?.stops ?? const [];
    final status = itinerary?.statusFor(discovery.timeBudgetMinutes) ??
        ItineraryStatus.empty;

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, size: 17, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Your plan',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              AppBadge(
                label: '${stops.length} STOPS',
                color: AppColors.primary,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            stops.isEmpty
                ? 'Nothing added yet'
                : '${itinerary?.totalLabel} · ${itinerary?.costLabel} · '
                    'back by ${itinerary?.endAt != null ? _clock(itinerary!.endAt!) : '—'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 11),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: status.color.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(status.icon, size: 15, color: status.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status == ItineraryStatus.empty
                        ? 'Add a feasible option to start'
                        : '${status.label} · ${itinerary!.totalLabel} of '
                            '${discovery.timeLabel}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      color: status.color,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (stops.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < stops.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        _clock(stops[i].arriveAt),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stops[i].experienceId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          Text(
                            '${stops[i].activityMinutes} min · ₹${stops[i].cost}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => ref
                          .read(itineraryControllerProvider.notifier)
                          .remove(stops[i].id),
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/plan'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Open full plan'),
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime time) {
    final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m ${time.hour >= 12 ? 'PM' : 'AM'}';
  }
}

class _ExploreFooter extends ConsumerWidget {
  const _ExploreFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Wrap(
        spacing: 22,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              'LocalIQ evaluates every option against your real constraints '
              'rather than showing you everything nearby. Move any control and '
              'the ranking, the map and your plan all update together.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => context.push('/what-if'),
            icon: const Icon(Icons.tune_rounded, size: 17),
            label: const Text('What-if lab'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              ref.read(discoveryContextProvider.notifier).reset();
              showAppToast(
                context,
                'Constraints reset to the default window',
                icon: Icons.restart_alt_rounded,
              );
            },
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: const Text('Reset constraints'),
          ),
          AppBadge(
            label: 'Budget ${discovery.budgetLabel}',
            color: AppColors.violet,
            icon: Icons.payments_outlined,
          ),
        ],
      ),
    );
  }
}
