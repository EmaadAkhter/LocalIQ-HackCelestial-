import 'package:flutter/material.dart';

import 'place.dart';

/// User constraints driving the recommendation flow.
class SearchParams {
  const SearchParams({
    this.location = 'Bandra, Mumbai',
    this.latitude = 19.0596,
    this.longitude = 72.8295,
    this.timeHours = 2,
    this.budgetInr = 800,
    this.groupType = GroupType.family,
    this.interests = const <PlaceCategory>{
      PlaceCategory.food,
      PlaceCategory.culture,
    },
    this.accessibility = false,
    this.query = '',
    this.startTime,
  });

  final String location;
  final double latitude;
  final double longitude;
  final double timeHours;
  final int budgetInr;
  final GroupType groupType;
  final Set<PlaceCategory> interests;

  /// Requires wheelchair / step-free access.
  final bool accessibility;

  /// Natural-language query typed on Home.
  final String query;

  /// `HH:MM` or null for "right now".
  final String? startTime;

  SearchParams copyWith({
    String? location,
    double? latitude,
    double? longitude,
    double? timeHours,
    int? budgetInr,
    GroupType? groupType,
    Set<PlaceCategory>? interests,
    bool? accessibility,
    String? query,
    String? startTime,
    bool clearStartTime = false,
  }) {
    return SearchParams(
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timeHours: timeHours ?? this.timeHours,
      budgetInr: budgetInr ?? this.budgetInr,
      groupType: groupType ?? this.groupType,
      interests: interests ?? this.interests,
      accessibility: accessibility ?? this.accessibility,
      query: query ?? this.query,
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
    );
  }

  Map<String, dynamic> toApiJson() {
    return <String, dynamic>{
      'location': location,
      'time_hours': timeHours,
      'budget_inr': budgetInr,
      'group_type': groupType.name,
      'interests': interests.map((PlaceCategory c) => c.name).toList(),
      'accessibility': accessibility ? 'wheelchair-accessible' : null,
      'start_time': startTime,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is SearchParams &&
        other.location == location &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.timeHours == timeHours &&
        other.budgetInr == budgetInr &&
        other.groupType == groupType &&
        other.accessibility == accessibility &&
        other.query == query &&
        other.startTime == startTime &&
        other.interests.length == interests.length &&
        other.interests.containsAll(interests);
  }

  @override
  int get hashCode => Object.hash(
    location,
    latitude,
    longitude,
    timeHours,
    budgetInr,
    groupType,
    accessibility,
    query,
    startTime,
    Object.hashAll(interests),
  );
}

/// How the recommendation list is ordered.
enum SortOption {
  recommended('Recommended', Icons.auto_awesome_rounded),
  rating('Top rated', Icons.star_rounded),
  distance('Nearest', Icons.near_me_rounded),
  costLowToHigh('Cheapest', Icons.payments_outlined),
  durationShortest('Quickest', Icons.bolt_rounded);

  const SortOption(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Extra client-side filters applied after the API response.
class FilterOptions {
  const FilterOptions({
    this.maxCost,
    this.maxTravelMinutes,
    this.indoorOnly = false,
    this.openOnly = true,
  });

  final int? maxCost;
  final int? maxTravelMinutes;
  final bool indoorOnly;
  final bool openOnly;

  FilterOptions copyWith({
    int? maxCost,
    int? maxTravelMinutes,
    bool? indoorOnly,
    bool? openOnly,
    bool clearCost = false,
    bool clearTravel = false,
  }) {
    return FilterOptions(
      maxCost: clearCost ? null : (maxCost ?? this.maxCost),
      maxTravelMinutes: clearTravel
          ? null
          : (maxTravelMinutes ?? this.maxTravelMinutes),
      indoorOnly: indoorOnly ?? this.indoorOnly,
      openOnly: openOnly ?? this.openOnly,
    );
  }
}
