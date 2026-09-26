import 'package:flutter/foundation.dart';

import '../../../core/utils/json_map_x.dart';
import 'context_models.dart';

/// The full set of live constraints that drive feasibility. Persisted per
/// user and recomputed whenever any input changes.
@immutable
class DiscoveryContext {
  const DiscoveryContext({
    required this.locationLabel,
    required this.centre,
    required this.timeBudgetMinutes,
    required this.startTime,
    required this.budget,
    required this.interests,
    required this.groupType,
    required this.accessibility,
    required this.localBias,
    required this.query,
    this.maxTravelMinutes = 25,
  });

  final String locationLabel;
  final GeoPoint centre;

  /// How long the user says they have.
  final int timeBudgetMinutes;

  /// When they are starting. Determines opening-hours checks.
  final DateTime startTime;

  final int budget;
  final Set<ExperienceCategory> interests;
  final GroupType groupType;
  final AccessibilityNeed accessibility;

  /// 0 = pure local gems, 1 = fully tourist-facing.
  final double localBias;

  final String query;
  final int maxTravelMinutes;

  int get endTimeMinutes =>
      startTime.hour * 60 + startTime.minute + timeBudgetMinutes;

  /// Coordinate record matching the map and routing layers.
  ({double lat, double lng}) get pin =>
      (lat: centre.latitude, lng: centre.longitude);

  String get timeLabel => formatMinutes(timeBudgetMinutes);

  String get budgetLabel => '₹$budget';

  String get interestsLabel => interests.isEmpty
      ? 'anything'
      : interests.take(3).map((i) => i.label.toLowerCase()).join(', ');

  /// Single-line description used on cards, the plan header and the assistant.
  String get summaryLine =>
      '$timeLabel in $locationLabel · $budgetLabel budget · $interestsLabel';

  DateTime get endTime => startTime.add(Duration(minutes: timeBudgetMinutes));

  static String formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return h == 1 ? '1 hour' : '$h hours';
    return '${h}h ${m}m';
  }

  DiscoveryContext copyWith({
    String? locationLabel,
    GeoPoint? centre,
    int? timeBudgetMinutes,
    DateTime? startTime,
    int? budget,
    Set<ExperienceCategory>? interests,
    GroupType? groupType,
    AccessibilityNeed? accessibility,
    double? localBias,
    String? query,
    int? maxTravelMinutes,
  }) {
    return DiscoveryContext(
      locationLabel: locationLabel ?? this.locationLabel,
      centre: centre ?? this.centre,
      timeBudgetMinutes: timeBudgetMinutes ?? this.timeBudgetMinutes,
      startTime: startTime ?? this.startTime,
      budget: budget ?? this.budget,
      interests: interests ?? this.interests,
      groupType: groupType ?? this.groupType,
      accessibility: accessibility ?? this.accessibility,
      localBias: localBias ?? this.localBias,
      query: query ?? this.query,
      maxTravelMinutes: maxTravelMinutes ?? this.maxTravelMinutes,
    );
  }

  factory DiscoveryContext.fromJson(Map<String, dynamic> json) {
    final interests = json
        .stringList('interests')
        .map((value) => ExperienceCategory.parse(value))
        .toSet();
    return DiscoveryContext(
      locationLabel: json.string('locationLabel') ?? 'Mumbai',
      centre: GeoPoint.fromJson(json.mapOrEmpty('centre')),
      timeBudgetMinutes: json.intValue('timeBudgetMinutes', fallback: 120),
      startTime: DateTime.tryParse(json.stringOrNull('startTime') ?? '') ??
          DateTime.now(),
      budget: json.intValue('budget', fallback: 1000),
      interests: interests.isEmpty ? {ExperienceCategory.food} : interests,
      groupType: GroupType.parse(json.string('groupType')),
      accessibility: AccessibilityNeed.parse(json.string('accessibility')),
      localBias: json.doubleValue('localBias', fallback: 0.3),
      query: json.string('query') ?? '',
      maxTravelMinutes: json.intValue('maxTravelMinutes', fallback: 25),
    );
  }

  Map<String, dynamic> toJson() => {
        'location_label': locationLabel,
        'centre': centre.toJson(),
        'time_budget_minutes': timeBudgetMinutes,
        'start_time': startTime.toIso8601String(),
        'budget': budget,
        'interests': interests.map((i) => i.name).toList(),
        'group_type': groupType.name,
        'accessibility': accessibility.name,
        'local_bias': localBias,
        'query': query,
        'max_travel_minutes': maxTravelMinutes,
      };
}
