import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/place_image.dart';
import '../../core/widgets/status_widgets.dart';
import '../../models/place.dart';
import '../../services/directions_service.dart';

/// Place details — fifth reference frame.
class PlaceDetailsScreen extends StatelessWidget {
  const PlaceDetailsScreen({required this.place, super.key});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final SearchSnapshot snap = SearchSnapshot.of(state);
    final bool isOpen = place.isOpenAt(DateTime.now());
    final bool saved = state.isInItinerary(place.id);
    final bool favourite = state.isFavourite(place.id);
    final double distanceKm = place.distanceFrom(snap.lat, snap.lng);
    final int travelMinutes = place.travelFrom(snap.lat, snap.lng);
    final int totalMinutes = place.durationMin + travelMinutes * 2 + 20;

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.all(6),
              child: _CircleButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.all(6),
                child: _CircleButton(
                  icon: favourite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  iconColor: favourite
                      ? AppColors.closed
                      : AppColors.textPrimary,
                  onTap: () => state.toggleFavourite(place.id),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  PlaceImage(
                    imageUrl: place.imageUrl,
                    seed: place.name,
                    icon: place.category.icon,
                    width: double.infinity,
                    height: 280,
                    borderRadius: BorderRadius.zero,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[Color(0x66000000), Color(0x00000000)],
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -18),
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.lg,
                  Insets.page,
                  Insets.xl,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(Radii.xl),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            place.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.15,
                            ),
                          ),
                        ),
                        OpenStatusPill(isOpen: isOpen),
                      ],
                    ),
                    const SizedBox(height: 6),
                    RatingRow(
                      rating: place.rating,
                      reviewCount: place.reviewCount,
                      size: 15,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${place.category.label} · ${place.area} · '
                      '${_budgetLabel(place.avgCost)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: Insets.lg),
                    _InfoGrid(
                      travelMinutes: travelMinutes,
                      distanceKm: distanceKm,
                      cost: place.avgCost,
                      hours: Fmt.timeRange(place.openTime, place.closeTime),
                      durationMin: place.durationMin,
                      totalMinutes: totalMinutes,
                    ),
                    const SizedBox(height: Insets.xl),
                    const _Heading('About'),
                    const SizedBox(height: 6),
                    Text(
                      place.description,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (place.tags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: Insets.md),
                      Wrap(
                        spacing: Insets.sm,
                        runSpacing: Insets.sm,
                        children: <Widget>[
                          for (final String tag in place.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(Radii.pill),
                              ),
                              child: Text(
                                '#$tag',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: Insets.xl),
                    const _Heading('Why Recommended?'),
                    const SizedBox(height: Insets.sm),
                    ..._reasons(place, snap).map(
                      (String reason) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 17,
                              color: AppColors.open,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                reason,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: Insets.lg),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (saved) {
                                state.removeFromItinerary(place.id);
                              } else {
                                state.addPlaceToItinerary(place);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    saved
                                        ? 'Removed from your plan'
                                        : 'Added to your itinerary',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: Icon(
                              saved
                                  ? Icons.playlist_add_check_rounded
                                  : Icons.playlist_add_rounded,
                              size: 19,
                            ),
                            label: Text(
                              saved ? 'In Itinerary' : 'Add to Itinerary',
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              final bool ok = await const DirectionsService()
                                  .openDirections(
                                    lat: place.lat,
                                    lng: place.lng,
                                    originLat: snap.lat,
                                    originLng: snap.lng,
                                    label: place.name,
                                  );
                              if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not open maps on this device',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(
                              Icons.directions_rounded,
                              size: 19,
                            ),
                            label: const Text('Get Directions'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.md),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => goToChat(context, place: place),
                        icon: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        label: const Text('Ask the AI guide about this place'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _budgetLabel(int cost) {
    if (cost <= 0) return 'Free';
    return 'Budget friendly';
  }

  static List<String> _reasons(Place place, SearchSnapshot snap) {
    final reasons = <String>[];
    if (place.avgCost <= snap.budgetInr) {
      reasons.add('Fits your budget (${Fmt.inrExact(snap.budgetInr)})');
    }
    if (place.durationMin <= snap.timeHours * 60) {
      final int h = snap.timeHours.round();
      reasons.add('Works inside your ${h == 1 ? '1 hour' : '$h hours'}');
    }
    if (place.isStepFree) reasons.add('Step-free and easy to reach');
    if (place.rating >= 4.5) {
      reasons.add('Highly rated (${place.rating.toStringAsFixed(1)}★)');
    }
    if (place.localGemScore >= 0.85) {
      reasons.add('Loved by locals, not just tourists');
    }
    if (place.indoorOutdoor == IndoorOutdoor.indoor) {
      reasons.add('Indoor, so the weather cannot ruin it');
    }
    reasons.add('Close to other recommended places');
    return reasons.take(5).toList();
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({
    required this.travelMinutes,
    required this.distanceKm,
    required this.cost,
    required this.hours,
    required this.durationMin,
    required this.totalMinutes,
  });

  final int travelMinutes;
  final double distanceKm;
  final int cost;
  final String hours;
  final int durationMin;
  final int totalMinutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _InfoCell(
                  icon: Icons.directions_walk_rounded,
                  value: '$travelMinutes min',
                  label: 'from you',
                ),
              ),
              Expanded(
                child: _InfoCell(
                  icon: Icons.straighten_rounded,
                  value: '${distanceKm.toStringAsFixed(1)} km',
                  label: 'away',
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Insets.md),
            child: Divider(height: 1),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: _InfoCell(
                  icon: Icons.payments_outlined,
                  value: Fmt.inrExact(cost),
                  label: 'for two',
                ),
              ),
              Expanded(
                child: _InfoCell(
                  icon: Icons.schedule_rounded,
                  value: hours,
                  label: isOpenLabel,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Insets.md),
            child: Divider(height: 1),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: _InfoCell(
                  icon: Icons.timer_outlined,
                  value: Fmt.duration(durationMin),
                  label: 'visit',
                ),
              ),
              Expanded(
                child: _InfoCell(
                  icon: Icons.route_rounded,
                  value: Fmt.duration(totalMinutes),
                  label: 'with travel',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String get isOpenLabel => 'today';
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 17, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
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

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }
}

/// Read-only projection of the active search for the details screen.
class SearchSnapshot {
  const SearchSnapshot({
    required this.lat,
    required this.lng,
    required this.budgetInr,
    required this.timeHours,
  });

  factory SearchSnapshot.of(AppState state) {
    return SearchSnapshot(
      lat: state.params.latitude,
      lng: state.params.longitude,
      budgetInr: state.params.budgetInr,
      timeHours: state.params.timeHours,
    );
  }

  final double lat;
  final double lng;
  final int budgetInr;
  final double timeHours;
}
