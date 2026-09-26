import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_image.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../context/application/discovery_context_controller.dart';
import '../../../recommendations/application/recommendation_controller.dart';
import '../../../recommendations/domain/recommendation.dart';
import '../../../routing/presentation/localiq_map_view.dart';
import '../../application/plan_providers.dart';
import '../../domain/place.dart';

/// Horizontal rail of places, resolved to their best live experience so the
/// card shows a current feasibility verdict rather than static data.
class DiscoveryRail extends ConsumerWidget {
  const DiscoveryRail({
    super.key,
    required this.title,
    required this.subtitle,
    required this.places,
    required this.icon,
    this.badgeLabel,
  });

  final String title;
  final String subtitle;
  final List<Place> places;
  final IconData icon;
  final String? badgeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (places.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: title,
          subtitle: subtitle,
          icon: icon,
          trailing: badgeLabel == null
              ? null
              : AppBadge(
                  label: badgeLabel!,
                  color: AppColors.violet,
                  dense: true,
                ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 226,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.only(bottom: 6),
            itemCount: places.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) => SizedBox(
              width: 234,
              child: _PlaceCard(place: places[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceCard extends ConsumerWidget {
  const _PlaceCard({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(recommendationControllerProvider).value;
    // The best available experience at this place, for the live verdict.
    Recommendation? best;
    if (result != null) {
      for (final rec in result.recommendations) {
        if (rec.place.id != place.id) continue;
        if (best == null || rec.score > best.score) best = rec;
      }
    }

    final tone = best?.tier.color ?? AppColors.textMuted;
    final inPlan = ref.watch(
      itineraryPlannedProvider(place.id),
    );

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: best == null
            ? null
            : () => context.push('/place/${best!.experience.id}?place=${place.id}'),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.card,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg - 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    AppImage(
                      url: place.heroImageUrl,
                      height: 104,
                      tint: categoryColor(place.category),
                      borderRadius: BorderRadius.zero,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: AppBadge(
                        label: place.localFavourite
                            ? 'LOCAL FAVOURITE'
                            : place.category.label.toUpperCase(),
                        color: categoryColor(place.category),
                        filled: true,
                        dense: true,
                      ),
                    ),
                    Positioned(
                      left: 9,
                      bottom: 8,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: AppColors.star,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            place.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            ' · ${_compact(place.reviewCount)}',
                            style: const TextStyle(
                              color: Color(0xFFD5DEEC),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          place.area,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            AppBadge(
                              label: best?.tier.label ?? 'Checking…',
                              color: tone,
                              dense: true,
                            ),
                            const Spacer(),
                            if (inPlan)
                              const Icon(
                                Icons.playlist_add_check_rounded,
                                size: 15,
                                color: AppColors.success,
                              ),
                          ],
                        ),
                        if (best != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            '${best.outboundTravel.minutes} min · '
                            '${best.experience.priceLabel}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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

/// Whether any experience at a place is in the plan.
final itineraryPlannedProvider = Provider.family<bool, String>((ref, placeId) {
  final itinerary = ref.watch(itineraryForPlanProvider).value;
  if (itinerary == null) return false;
  return itinerary.stops.any((s) => s.placeId == placeId);
});

/// Map preview card with live pins reflecting the current ranking.
class MapPreviewPanel extends ConsumerWidget {
  const MapPreviewPanel({super.key, this.height = 250, this.pinLimit = 6});

  final double height;
  final int pinLimit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    final result = ref.watch(recommendationControllerProvider).value;
    final planned = ref.watch(itineraryForPlanProvider).value;
    final pins = <PlacePin>[];
    if (result != null) {
      for (final rec in result.byTier.take(pinLimit)) {
        pins.add(
          PlacePin(
            id: rec.experience.id,
            label: rec.experience.title,
            position: (lat: rec.place.centre.latitude, lng: rec.place.centre.longitude),
            tone: switch (rec.tier) {
              FeasibilityTier.feasible => 'feasible',
              FeasibilityTier.partial => 'partial',
              FeasibilityTier.notFeasible => 'blocked',
            },
            onTap: () => context.push(
              '/place/${rec.experience.id}?place=${rec.place.id}',
            ),
          ),
        );
      }
    }

    final route = <({double lat, double lng})>[];
    if (planned != null) {
      route.add((lat: discovery.centre.latitude, lng: discovery.centre.longitude));
      for (final stop in planned.stops) {
        final point = ref.watch(placeCentreProvider(stop.placeId));
        if (point != null) route.add(point);
      }
    }

    return AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: SectionHeading(
              title: 'Map',
              subtitle: '${discovery.locationLabel} · pins reflect the live ranking',
              icon: Icons.map_outlined,
            ),
          ),
          LocalIqMapView(
            pins: pins,
            route: route,
            userLocation: (
              lat: discovery.centre.latitude,
              lng: discovery.centre.longitude,
            ),
            height: height,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: const MapLegend(),
          ),
        ],
      ),
    );
  }
}

/// Resolves a place's coordinates for map overlays.
final placeCentreProvider =
    Provider.family<({double lat, double lng})?, String>((ref, placeId) {
  final place = ref.watch(placeByIdProvider(placeId));
  if (place == null) return null;
  return (lat: place.centre.latitude, lng: place.centre.longitude);
});
