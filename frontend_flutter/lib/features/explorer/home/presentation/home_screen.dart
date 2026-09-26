import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/right_now_context.dart';
import '../../../places/domain/place.dart';
import '../widgets/home_header.dart';
import '../widgets/quick_chips.dart';
import '../widgets/right_now_banner.dart';
import '../widgets/home_section.dart';
import '../widgets/experience_card.dart';
import '../widgets/guide_card.dart';
import '../../../../models/quest.dart';
import '../../../guides/data/guide_repository.dart';
import '../../../guides/data/local_guides.dart';
import '../../../quests/data/quest_repository.dart';
import '../../../quests/data/local_quests.dart';

/// Explorer Home — personalized discovery feed.
///
/// This is the primary mobile-first home experience for the Explorer role.
/// Replaces the old desktop-centric ExploreScreen as the landing page.
class ExplorerHomeScreen extends ConsumerStatefulWidget {
  const ExplorerHomeScreen({super.key});

  @override
  ConsumerState<ExplorerHomeScreen> createState() => _ExplorerHomeScreenState();
}

class _ExplorerHomeScreenState extends ConsumerState<ExplorerHomeScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placesAsync = ref.watch(allPlacesProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Header (location, weather, avatar)
          SliverToBoxAdapter(
            child: HomeHeader(user: user),
          ),

          // ── Primary heading + search
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    'What should we do?',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          letterSpacing: -0.8,
                          height: 1.1,
                        ),
                  ),
                  const SizedBox(height: 14),
                  _SearchField(
                    controller: _searchController,
                    onTap: () => context.push('/discover'),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),

          // ── Quick chips
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(left: 20, bottom: 20),
              child: QuickChips(),
            ),
          ),

          // ── Right Now banner
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: RightNowBanner(context: RightNowContext.sample),
            ),
          ),

          // ── Feed sections
          placesAsync.when(
            data: (places) => _HomeFeed(places: places),
            loading: () => const SliverToBoxAdapter(child: _HomeLoading()),
            error: (e, _) => SliverToBoxAdapter(
              child: _HomeError(onRetry: () => ref.invalidate(allPlacesProvider)),
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onTap,
  });

  final TextEditingController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Tell LocalIQ what you're looking for...",
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              margin: const EdgeInsets.all(6),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeFeed extends ConsumerWidget {
  const _HomeFeed({required this.places});

  final List<Place> places;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (places.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Text(
              'No experiences found nearby.',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
        ),
      );
    }

    final sorted = [...places]..sort((a, b) => b.rating.compareTo(a.rating));
    final recommended = sorted.take(8).toList();
    final gems = places.where((p) => p.localFavourite).take(6).toList();
    final nearbyGuides = ref.watch(allGuidesProvider).value ?? kLocalGuides;

    return SliverList(
      delegate: SliverChildListDelegate([
        // 1. Recommended for you
        HomeSection(
          title: 'Recommended for you',
          subtitle: 'Based on your location and preferences',
          icon: Icons.auto_awesome_rounded,
          iconColor: AppColors.violet,
          onSeeAll: () => context.push('/discover'),
          child: SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: recommended.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => ExperienceCard(
                place: recommended[i],
                onTap: () => context.push(
                  '/place/${recommended[i].id}',
                  extra: recommended[i],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // 2. Perfect right now
        HomeSection(
          title: 'Perfect right now',
          subtitle: 'Clear skies · Low crowd · 29°C',
          icon: Icons.bolt_rounded,
          iconColor: const Color(0xFF0E7C5A),
          onSeeAll: () => context.push('/discover?filter=right_now'),
          child: SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: sorted.take(6).length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final list = sorted.take(6).toList();
                return ExperienceCard(
                  place: list[i],
                  rightNowLabel: 'Great right now',
                  onTap: () => context.push('/place/${list[i].id}'),
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 8),

        // 3. Hidden gems near you
        HomeSection(
          title: 'Hidden gems near you',
          subtitle: 'Locals rate highly, visitors rarely find',
          icon: Icons.diamond_outlined,
          iconColor: AppColors.violet,
          onSeeAll: () => context.push('/discover?filter=gems'),
          child: SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: gems.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => ExperienceCard(
                place: gems[i],
                isLocalGem: true,
                onTap: () => context.push('/place/${gems[i].id}'),
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // 4. Local guides near you
        HomeSection(
          title: 'Local guides near you',
          subtitle: 'Verified guides available today',
          icon: Icons.person_search_outlined,
          iconColor: AppColors.blue,
          onSeeAll: () => context.push('/guides'),
          child: SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: nearbyGuides.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => GuideCard(
                guide: nearbyGuides[i],
                onTap: () => context.push('/guides'),
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // 5. Active Plan teaser
        const _ActivePlanTeaser(),

        const SizedBox(height: 8),

        // 6. Quests teaser
        const _QuestsTeaser(),

        const SizedBox(height: 24),
      ]),
    );
  }
}

class _ActivePlanTeaser extends ConsumerWidget {
  const _ActivePlanTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => context.go('/plan'),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppShadows.raised,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.route_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your active plan',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Tap to view your itinerary and add stops',
                      style: TextStyle(
                        color: Color(0xFFFFF0E8),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestsTeaser extends ConsumerWidget {
  const _QuestsTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(allQuestsProvider).value ?? kLocalQuests;

    return HomeSection(
      title: 'Quests',
      subtitle: 'Curated multi-stop local adventures',
      icon: Icons.explore_outlined,
      iconColor: const Color(0xFFB07514),
      onSeeAll: () => context.push('/quests'),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: quests
              .map((q) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _QuestChip(
                      title: q.title,
                      emoji: q.tags.contains('Food Trail')
                          ? '🍜'
                          : q.tags.contains('Heritage')
                              ? '🏛️'
                              : '🎨',
                      color: q.difficulty.color,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _QuestChip extends StatelessWidget {
  const _QuestChip({
    required this.title,
    required this.emoji,
    required this.color,
  });

  final String title;
  final String emoji;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/quests'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _skeletonRow(context, label: 'Recommended for you'),
          const SizedBox(height: 20),
          _skeletonRow(context, label: 'Perfect right now'),
          const SizedBox(height: 20),
          _skeletonRow(context, label: 'Hidden gems'),
        ],
      ),
    );
  }

  Widget _skeletonRow(BuildContext context, {required String label}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Skeleton(height: 18, width: 180),
        const SizedBox(height: 10),
        Row(
          children: List.generate(
            3,
            (i) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _Skeleton(height: 200, width: 160),
            ),
          ),
        ),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height, required this.width});

  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          const Text('Could not load experiences',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
