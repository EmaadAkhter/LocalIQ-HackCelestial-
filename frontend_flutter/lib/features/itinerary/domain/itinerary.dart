import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json_map_x.dart';
import '../../context/domain/discovery_context.dart';

/// One stop in a plan, resolved against the itinerary's own sequence.
@immutable
class ItineraryStop {
  const ItineraryStop({
    required this.id,
    required this.experienceId,
    required this.placeId,
    required this.position,
    required this.arriveAt,
    required this.departAt,
    required this.travelInMinutes,
    required this.travelToMinutes,
    required this.activityMinutes,
    required this.cost,
    required this.locked,
    this.notes,
  });

  final String id;
  final String experienceId;
  final String placeId;

  /// Zero-based order in the itinerary.
  final int position;

  final DateTime arriveAt;
  final DateTime departAt;

  /// Travel from the previous stop.
  final int travelInMinutes;

  /// Travel back to the origin (only used by the final stop).
  final int travelToMinutes;

  final int activityMinutes;
  final int cost;

  /// Pinned stops are never auto-optimised away by the re-check.
  final bool locked;
  final String? notes;

  int get totalMinutes => travelInMinutes + activityMinutes;

  factory ItineraryStop.fromJson(Map<String, dynamic> json) {
    final arrive = DateTime.tryParse(json.stringOrNull('arriveAt') ?? '') ??
        DateTime.now();
    return ItineraryStop(
      id: json.string('id') ?? '',
      experienceId: json.string('experienceId') ?? '',
      placeId: json.string('placeId') ?? '',
      position: json.intValue('position'),
      arriveAt: arrive,
      departAt: DateTime.tryParse(json.stringOrNull('departAt') ?? '') ??
          arrive.add(const Duration(minutes: 30)),
      travelInMinutes: json.intValue('travelInMinutes'),
      travelToMinutes: json.intValue('travelToMinutes'),
      activityMinutes: json.intValue('activityMinutes', fallback: 45),
      cost: json.intValue('cost'),
      locked: json.boolValue('locked'),
      notes: json.stringOrNull('notes'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'experience_id': experienceId,
        'place_id': placeId,
        'position': position,
        'arrive_at': arriveAt.toIso8601String(),
        'depart_at': departAt.toIso8601String(),
        'travel_in_minutes': travelInMinutes,
        'travel_to_minutes': travelToMinutes,
        'activity_minutes': activityMinutes,
        'cost': cost,
        'locked': locked,
        'notes': notes,
      };
}

/// Plan-level verdict, independent of any single stop.
enum ItineraryStatus {
  onTrack('On track', AppColors.success, Icons.verified_rounded),
  tight('Tight', AppColors.warning, Icons.schedule_rounded),
  overrunning('Overrunning', AppColors.danger, Icons.error_outline_rounded),
  empty('Empty', AppColors.textMuted, Icons.route_rounded);

  const ItineraryStatus(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;
}

/// A complete plan with derived totals. `copyWith` on the stop list is managed
/// by the itinerary service, not the UI.
@immutable
class Itinerary {
  const Itinerary({
    required this.id,
    required this.userId,
    required this.title,
    required this.originLabel,
    required this.origin,
    required this.stops,
    required this.createdAt,
    required this.updatedAt,
    this.returnBufferMinutes = 12,
    this.savedAt,
  });

  final String id;
  final String userId;
  final String title;

  /// Where the plan starts and ends (typically the user's location).
  final String originLabel;
  final ({double lat, double lng}) origin;

  final List<ItineraryStop> stops;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Slack reserved at the end for delays and getting home.
  final int returnBufferMinutes;
  final DateTime? savedAt;

  bool get isEmpty => stops.isEmpty;
  bool get isSaved => savedAt != null;

  int get stopCount => stops.length;

  int get activityMinutes =>
      stops.fold(0, (sum, stop) => sum + stop.activityMinutes);

  int get travelMinutes {
    if (stops.isEmpty) return 0;
    var total = 0;
    for (var i = 0; i < stops.length; i++) {
      total += i == 0
          ? stops[i].travelInMinutes
          : stops[i].travelInMinutes + stops[i].travelToMinutes;
    }
    return total;
  }

  int get totalCost => stops.fold(0, (sum, stop) => sum + stop.cost);

  int get totalMinutes => activityMinutes + travelMinutes + returnBufferMinutes;

  String get costLabel => totalCost == 0 ? 'Free' : '₹$totalCost';

  String get totalLabel => DiscoveryContext.formatMinutes(totalMinutes);

  DateTime? get endAt => stops.isEmpty ? null : stops.last.departAt;

  int slackAgainst(int availableMinutes) => availableMinutes - totalMinutes;

  /// The plan verdict for a given available window.
  ItineraryStatus statusFor(int availableMinutes) {
    if (stops.isEmpty) return ItineraryStatus.empty;
    final slack = slackAgainst(availableMinutes);
    if (slack < 0) return ItineraryStatus.overrunning;
    if (slack < 20) return ItineraryStatus.tight;
    return ItineraryStatus.onTrack;
  }

  Itinerary copyWith({
    String? title,
    List<ItineraryStop>? stops,
    DateTime? updatedAt,
    int? returnBufferMinutes,
    DateTime? savedAt,
    bool clearSaved = false,
  }) {
    return Itinerary(
      id: id,
      userId: userId,
      title: title ?? this.title,
      originLabel: originLabel,
      origin: origin,
      stops: stops ?? this.stops,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      returnBufferMinutes: returnBufferMinutes ?? this.returnBufferMinutes,
      savedAt: clearSaved ? null : (savedAt ?? this.savedAt),
    );
  }

  factory Itinerary.fromJson(Map<String, dynamic> json) {
    final centre = json.mapOrEmpty('origin');
    return Itinerary(
      id: json.string('id') ?? '',
      userId: json.string('userId') ?? '',
      title: json.string('title') ?? 'My plan',
      originLabel: json.string('originLabel') ?? 'Start',
      origin: (
        lat: centre.doubleValue('latitude'),
        lng: centre.doubleValue('longitude'),
      ),
      stops: json
          .mapList('stops')
          .map(ItineraryStop.fromJson)
          .toList(growable: false),
      createdAt:
          DateTime.tryParse(json.stringOrNull('createdAt') ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(json.stringOrNull('updatedAt') ?? '') ?? DateTime.now(),
      returnBufferMinutes: json.intValue('returnBufferMinutes', fallback: 12),
      savedAt: DateTime.tryParse(json.stringOrNull('savedAt') ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'origin_label': originLabel,
        'origin': {'latitude': origin.lat, 'longitude': origin.lng},
        'stops': [for (final stop in stops) stop.toJson()],
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'return_buffer_minutes': returnBufferMinutes,
        'saved_at': savedAt?.toIso8601String(),
      };
}
