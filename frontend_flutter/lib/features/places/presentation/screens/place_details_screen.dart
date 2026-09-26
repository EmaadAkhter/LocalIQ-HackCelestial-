import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_image.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../context/application/discovery_context_controller.dart';
import '../../../recommendations/application/recommendation_controller.dart';
import '../../../recommendations/domain/recommendation.dart';
import '../../../recommendations/presentation/widgets/recommendation_card.dart';
import '../../../routing/presentation/localiq_map_view.dart';
import '../../../saved/application/saved_controller.dart';
import '../../domain/place.dart';

class PlaceDetailsScreen extends ConsumerStatefulWidget {
  const PlaceDetailsScreen({
    super.key,
    required this.experienceId,
    this.placeId,
  });

  final String experienceId;
  final String? placeId;

  @override
  ConsumerState<PlaceDetailsScreen> createState() => _PlaceDetailsScreenState();
}

class _PlaceDetailsScreenState extends ConsumerState<PlaceDetailsScreen> {
  bool _whyOpen = true;

  @override
  Widget build(BuildContext context) {
    final placeAsync = widget.placeId != null
        ? ref.watch(placeDetailProvider(widget.placeId!))
        : AsyncValue.data(
            ref.watch(placeForExperienceProvider(widget.experienceId)),
          );

    return placeAsync.when(
      data: (resolvedPlace) {
        if (resolvedPlace == null) {
          return _Placeholder(
            icon: Icons.explore_off_rounded,
            title: 'Place not found',
            subtitle: 'We could not find that place. It may have been removed.',
            action: FilledButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.home_rounded, size: 18),
              label: const Text('Back to Home'),
            ),
          );
        }
        return _buildDetail(resolvedPlace);
      },
      loading: () => Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (error, stack) {
        final message =
            error is AppException ? error.message : 'Something went wrong';
        return _Placeholder(
          icon: Icons.error_outline_rounded,
          title: message,
          subtitle: 'Pull down to retry or go back to Explore.',
          action: FilledButton.icon(
            onPressed: () {
              if (widget.placeId != null) {
                ref.invalidate(placeDetailProvider(widget.placeId!));
              }
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        );
      },
    );
  }

  Widget _buildDetail(Place resolvedPlace) {
    final rec = ref.watch(recommendationByIdProvider(widget.experienceId));
    final width = MediaQuery.sizeOf(context).width;
    final desktop = Breakpoints.isDesktop(width);
    final gutter = Breakpoints.gutter(width);

    final overview = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleBlock(place: resolvedPlace, recommendation: rec),
        const SizedBox(height: 16),
        if (rec != null)
          _WhyRecommended(
            recommendation: rec,
            expanded: _whyOpen,
            onToggle: () => setState(() => _whyOpen = !_whyOpen),
          ),
        if (rec != null) const SizedBox(height: 18),
        _TimeBreakdown(place: resolvedPlace, recommendation: rec),
        const SizedBox(height: 18),
        const SectionHeading(
          title: 'Practical information',
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(height: 12),
        _PracticalInfo(place: resolvedPlace),
        const SizedBox(height: 18),
        _DirectionsBlock(place: resolvedPlace),
        const SizedBox(height: 18),
        _SimilarPlaces(place: resolvedPlace),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                _HeroAppBar(place: resolvedPlace, recommendation: rec),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 24),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: desktop
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 13, child: overview),
                                  const SizedBox(width: 20),
                                  SizedBox(
                                    width: 330,
                                    child: _BookingRail(
                                      place: resolvedPlace,
                                      recommendation: rec,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  overview,
                                  const SizedBox(height: 20),
                                  _BookingRail(
                                    place: resolvedPlace,
                                    recommendation: rec,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (rec != null)
            _ActionBar(place: resolvedPlace, recommendation: rec),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: AppColors.primary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 18),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final placeForExperienceProvider = Provider.family<Place?, String>((ref, id) {
  final experience = ref.watch(experienceByIdProvider(id));
  if (experience == null) return null;
  return ref.watch(placeByIdProvider(experience.placeId));
});

class _HeroAppBar extends ConsumerWidget {
  const _HeroAppBar({required this.place, required this.recommendation});

  final Place place;
  final Recommendation? recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final saved = ref.watch(isSavedProvider(recommendation?.experience.id ?? ''));

    return SliverAppBar(
      expandedHeight: width < 700 ? 220 : 300,
      pinned: true,
      stretch: true,
      backgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      leading: const BackButton(),
      actions: [
        if (recommendation != null)
          IconButton(
            tooltip: saved ? 'Remove from saved' : 'Save',
            onPressed: () {
              ref
                  .read(savedControllerProvider.notifier)
                  .toggle(recommendation!);
            },
            icon: Icon(
              saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: saved ? AppColors.danger : AppColors.primary,
            ),
          ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            AppImage(
              url: place.heroImageUrl,
              tint: categoryColor(place.category),
              borderRadius: BorderRadius.zero,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.navy.withValues(alpha: 0.35),
                    Colors.transparent,
                    AppColors.navy.withValues(alpha: 0.18),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends ConsumerWidget {
  const _TitleBlock({required this.place, required this.recommendation});

  final Place place;
  final Recommendation? recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = recommendation;
    final saved = rec != null && ref.watch(isSavedProvider(rec.experience.id));
    final discovery = ref.watch(discoveryContextProvider);
    final open = place.openingHours.isOpenAt(discovery.startTime);

    return AppPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              AppBadge(
                label: place.category.label.toUpperCase(),
                color: categoryColor(place.category),
                filled: true,
                dense: true,
              ),
              if (place.localFavourite)
                const AppBadge(
                  label: 'LOCAL FAVOURITE',
                  color: AppColors.violet,
                  icon: Icons.diamond_rounded,
                  dense: true,
                ),
              AppBadge(
                label: open ? 'Open at your arrival' : 'Closed at your arrival',
                icon: open ? Icons.check_circle_outline : Icons.do_not_disturb_on_outlined,
                color: open ? AppColors.success : AppColors.danger,
                dense: true,
              ),
              AppBadge(
                label: place.indoor ? 'Indoor' : 'Outdoor',
                icon: place.indoor ? Icons.weekend_rounded : Icons.park_rounded,
                color: AppColors.primary,
                dense: true,
              ),
              if (rec != null)
                AppBadge(
                  label: rec.tier.label,
                  icon: rec.tier.icon,
                  color: rec.tier.color,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            rec?.experience.title ?? place.name,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (rec != null) ...[
            const SizedBox(height: 6),
            Text(
              rec.experience.tagline,
              style: const TextStyle(
                fontSize: 14.5,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 19,
                    color: AppColors.star,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    place.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      ' · ${_compact(place.reviewCount)} reviews',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              MetaItem(
                icon: Icons.place_outlined,
                text: place.address,
                fontSize: 13,
              ),
              MetaItem(
                icon: Icons.payments_outlined,
                text: place.priceLabel,
                fontSize: 13,
              ),
              MetaItem(
                icon: Icons.schedule_rounded,
                text: place.openingHours.describeFor(
                  ref.watch(discoveryContextProvider).startTime,
                ),
                fontSize: 13,
              ),
              MetaItem(
                icon: Icons.groups_rounded,
                text: '${place.crowdLevel.label} right now',
                fontSize: 13,
              ),
              MetaItem(
                icon: Icons.accessible_rounded,
                text: place.accessibility.stepFree
                    ? 'Step-free access'
                    : 'Stairs on approach',
                fontSize: 13,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            place.summary ?? '',
            style: const TextStyle(fontSize: 14.5, height: 1.5),
          ),
          if (rec != null) ...[
            const SizedBox(height: 12),
            Text(
              rec.experience.description,
              style: const TextStyle(fontSize: 14.5, height: 1.5),
            ),
            if (rec.experience.practicalTip != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningSurface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 16,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        rec.experience.practicalTip!,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          if (rec != null) ...[
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: () {
                ref.read(savedControllerProvider.notifier).toggle(rec);
                showAppToast(
                  context,
                  saved ? 'Removed from saved' : 'Saved for later',
                  icon: saved ? Icons.heart_broken_rounded : Icons.favorite_rounded,
                );
              },
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              icon: Icon(
                saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 17,
              ),
              label: Text(saved ? 'Saved' : 'Save for later'),
            ),
          ],
        ],
      ),
    );
  }

  static String _compact(int value) {
    if (value >= 1000) {
      final k = value / 1000;
      return '${k >= 10 || k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}K';
    }
    return '$value';
  }
}

class _WhyRecommended extends StatelessWidget {
  const _WhyRecommended({
    required this.recommendation,
    required this.expanded,
    required this.onToggle,
  });

  final Recommendation recommendation;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final rec = recommendation;
    final passes = rec.constraints.where((c) => c.status == ConstraintStatus.pass);
    final caveats = rec.constraints.where((c) => c.status == ConstraintStatus.warn);
    final blocks = rec.constraints.where((c) => c.isBlocking);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.lavender,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: AppColors.violet,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Why LocalIQ recommends this',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          AnimatedSize(
            duration: AppMotion.medium,
            alignment: Alignment.topCenter,
            curve: AppMotion.curve,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (blocks.isNotEmpty) ...[
                          _ConstraintGroup(
                            title: 'What blocks it',
                            color: AppColors.danger,
                            results: blocks.toList(),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (caveats.isNotEmpty) ...[
                          _ConstraintGroup(
                            title: 'Trade-offs',
                            color: AppColors.warning,
                            results: caveats.toList(),
                          ),
                          const SizedBox(height: 14),
                        ],
                        _ConstraintGroup(
                          title: 'What works',
                          color: AppColors.success,
                          results: passes.toList(),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FieldLabel('Ranking logic'),
                              const SizedBox(height: 5),
                              Text(
                                rec.whyRanked,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.45,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _ConstraintGroup extends StatelessWidget {
  const _ConstraintGroup({
    required this.title,
    required this.color,
    required this.results,
  });

  final String title;
  final Color color;
  final List<ConstraintResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$title (${results.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final result in results)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    result.status == ConstraintStatus.pass
                        ? Icons.check_circle_rounded
                        : result.status == ConstraintStatus.warn
                            ? Icons.info_rounded
                            : Icons.block_rounded,
                    size: 16,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.detail,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TimeBreakdown extends ConsumerWidget {
  const _TimeBreakdown({required this.place, required this.recommendation});

  final Place place;
  final Recommendation? recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = recommendation;
    final live = ref.watch(liveContextProvider).value;

    final segments = <({String label, int minutes, Color color, IconData icon})>[
      (
        label: 'Travel there',
        minutes: rec?.outboundTravel.minutes ?? 0,
        color: AppColors.blue,
        icon: Icons.directions_walk_rounded,
      ),
      (
        label: 'Experience',
        minutes: rec?.experience.activityMinutes ?? 0,
        color: AppColors.violet,
        icon: Icons.explore_outlined,
      ),
      (
        label: 'Return',
        minutes: rec?.returnTravel.minutes ?? 0,
        color: AppColors.primary,
        icon: Icons.arrow_back_rounded,
      ),
    ];
    final total = rec?.completableMinutes ?? 0;

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading(
            title: 'Time and cost',
            subtitle: 'How the visit actually breaks down right now',
            icon: Icons.timeline_rounded,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final segment in segments)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(segment.icon, size: 14, color: segment.color),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              segment.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${segment.minutes} min',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: segment.color,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final segment in segments)
                      if (segment.minutes > 0)
                        Expanded(
                          flex: segment.minutes,
                          child: Container(color: segment.color),
                        ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (rec != null)
                AppBadge(
                  label: 'Total $total min',
                  icon: Icons.timelapse_rounded,
                  color: rec.tier.color,
                ),
              AppBadge(
                label: place.priceLabel,
                icon: Icons.payments_outlined,
                color: place.typicalSpend == 0
                    ? AppColors.success
                    : AppColors.violet,
              ),
              AppBadge(
                label: place.bookingRequired ? 'Booking required' : 'Walk-in',
                icon: place.bookingRequired
                    ? Icons.confirmation_num_outlined
                    : Icons.door_front_door_outlined,
                color: place.bookingRequired
                    ? AppColors.warning
                    : AppColors.primary,
              ),
              if (live != null)
                AppBadge(
                  label: live.traffic.label,
                  icon: Icons.traffic_rounded,
                  color: AppColors.blue,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PracticalInfo extends ConsumerWidget {
  const _PracticalInfo({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    final rows = <({IconData icon, String label, String value})>[
      (
        icon: Icons.schedule_rounded,
        label: 'Opening hours today',
        value: place.openingHours.describeFor(discovery.startTime),
      ),
      (
        icon: Icons.bookmark_border_rounded,
        label: 'Booking',
        value: place.bookingRequired ? 'Required' : 'Not required',
      ),
      (
        icon: Icons.groups_rounded,
        label: 'Crowd level',
        value: place.crowdLevel.label,
      ),
      (
        icon: Icons.accessible_rounded,
        label: 'Step-free',
        value: place.accessibility.stepFree ? 'Yes' : 'No',
      ),
      (
        icon: Icons.chair_alt_rounded,
        label: 'Seating',
        value: place.accessibility.seatingAvailable ? 'Available' : 'Limited',
      ),
      (
        icon: Icons.wc_rounded,
        label: 'Restrooms',
        value: place.accessibility.restrooms ? 'On site' : 'None',
      ),
      (
        icon: Icons.umbrella_rounded,
        label: 'Weather exposure',
        value: place.indoor ? 'Indoor' : 'Open air',
      ),
      (
        icon: Icons.diamond_outlined,
        label: 'Local appeal',
        value: '${(place.rating * 20).round()}/100',
      ),
      (
        icon: Icons.my_location_rounded,
        label: 'Coordinates',
        value: '${place.centre.latitude.toStringAsFixed(4)}, '
            '${place.centre.longitude.toStringAsFixed(4)}',
      ),
    ];

    return AppPanel(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 18),
            Row(
              children: [
                Icon(rows[i].icon, size: 16, color: AppColors.violet),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    rows[i].label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    rows[i].value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DirectionsBlock extends ConsumerWidget {
  const _DirectionsBlock({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: 'Getting there',
            subtitle: 'Estimated from ${discovery.locationLabel}',
            icon: Icons.directions_walk_rounded,
            trailing: FilledButton.tonalIcon(
              onPressed: () => showDirectionsSheet(context, place),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Open'),
            ),
          ),
          const SizedBox(height: 14),
          LocalIqMapView(
            pins: [
              PlacePin(
                id: place.id,
                label: place.name,
                position: (
                  lat: place.centre.latitude,
                  lng: place.centre.longitude,
                ),
                tone: 'user',
                selected: true,
              ),
            ],
            userLocation: (
              lat: discovery.centre.latitude,
              lng: discovery.centre.longitude,
            ),
            height: 180,
            showLabels: false,
          ),
          const SizedBox(height: 12),
          const MapLegend(showRoute: false),
        ],
      ),
    );
  }
}

class _SimilarPlaces extends ConsumerWidget {
  const _SimilarPlaces({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(allPlacesProvider).value ?? const <Place>[];
    final similar = places
        .where((p) => p.id != place.id)
        .where((p) =>
            p.category == place.category ||
            p.area == place.area ||
            p.localFavourite == place.localFavourite)
        .take(4)
        .toList();

    if (similar.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          title: 'Nearby alternatives',
          subtitle: 'Swaps if this one does not fit',
          icon: Icons.swap_horiz_rounded,
        ),
        const SizedBox(height: 12),
        for (final item in similar)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppPanel(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              onTap: () => context.push(
                '/place/${item.id}?place=${item.id}',
              ),
              child: Row(
                children: [
                  AppImage(
                    url: item.heroImageUrl,
                    width: 54,
                    height: 54,
                    tint: categoryColor(item.category),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${item.area} · ${item.priceLabel} · '
                          '${item.rating.toStringAsFixed(1)}★',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BookingRail extends ConsumerWidget {
  const _BookingRail({required this.place, required this.recommendation});

  final Place place;
  final Recommendation? recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = recommendation;
    return Column(
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add to your plan',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              if (rec != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: rec.tier.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(rec.tier.icon, size: 16, color: rec.tier.color),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          rec.verdict,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            color: rec.tier.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (rec != null) PlanToggleButton(recommendation: rec),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                onPressed: () => showDirectionsSheet(context, place),
                icon: const Icon(Icons.directions_rounded, size: 17),
                label: const Text('Directions'),
              ),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.home_rounded, size: 17),
                label: const Text('Back to Home'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (rec != null)
          AppPanel(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Alternatives at this place'),
                const SizedBox(height: 10),
                for (final other in ref.watch(experiencesAtPlaceProvider(place.id)))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: other.id == rec.experience.id
                          ? null
                          : () => context.push(
                                '/place/${other.id}?place=${place.id}',
                              ),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              other.id == rec.experience.id
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 15,
                              color: other.id == rec.experience.id
                                  ? AppColors.violet
                                  : AppColors.borderStrong,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                other.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${other.activityMinutes} min',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

final experiencesAtPlaceProvider =
    Provider.family<List<Experience>, String>((ref, placeId) {
  final all = ref.watch(allExperiencesProvider).value ?? const [];
  return all.where((e) => e.placeId == placeId).toList();
});

class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.place, required this.recommendation});

  final Place place;
  final Recommendation? recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = recommendation;
    if (rec == null) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Row(
                children: [
                  Expanded(flex: 3, child: PlanToggleButton(recommendation: rec)),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () => showDirectionsSheet(context, place),
                      icon: const Icon(Icons.directions_rounded, size: 17),
                      label: const Text('Directions'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showDirectionsSheet(BuildContext context, Place place) {
  final host = context;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Directions · ${place.name}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Route resolved from your current starting point.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                DirectionsLegs(placeId: place.id),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showAppToast(
                      host,
                      'Opening turn-by-turn navigation',
                      icon: Icons.navigation_rounded,
                    );
                  },
                  icon: const Icon(Icons.navigation_rounded, size: 17),
                  label: const Text('Start navigation'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Resolves and renders the leg breakdown for a place.
class DirectionsLegs extends ConsumerWidget {
  const DirectionsLegs({super.key, required this.placeId});

  final String? placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    final places = ref.watch(allPlacesProvider).value ?? const <Place>[];
    final Place? place;
    if (placeId == null) {
      place = places.isNotEmpty ? places.first : null;
    } else {
      final matches = places.where((p) => p.id == placeId);
      place = matches.isEmpty ? null : matches.first;
    }
    if (place == null) return const SizedBox.shrink();

    final from = discovery.centre;
    final to = place.centre;
    final km = _haversine(from.latitude, from.longitude, to.latitude, to.longitude);
    final mode = km < 1.2
        ? TravelMode.walk
        : km < 4.5
            ? TravelMode.transit
            : TravelMode.taxi;
    final speed = switch (mode) {
      TravelMode.walk => 4.6,
      TravelMode.bike => 14,
      TravelMode.transit => 17,
      TravelMode.taxi => 24,
    };
    final minutes = math.max(2, ((km * 1.32 / speed) * 60).round());

    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.place_rounded, size: 18, color: AppColors.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'From ${discovery.locationLabel}',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
            ),
            Text(
              '$minutes min',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Container(width: 2, height: 16, color: AppColors.border),
              const SizedBox(width: 10),
              Text(
                '${mode.label} · ${km.toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            const Icon(Icons.flag_rounded, size: 18, color: AppColors.violet),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                place.name,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
            ),
            Text(
              place.area,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static double _haversine(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lon2 - lon1);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) *
            math.sin(dLng / 2) *
            math.cos(_rad(lat1)) *
            math.cos(_rad(lat2));
    return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
  }

  static double _rad(double degrees) => degrees * math.pi / 180.0;
}
