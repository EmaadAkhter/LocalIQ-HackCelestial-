import 'package:flutter/material.dart';

import '../core/utils/geo.dart';

/// A place as returned by the LocalIQ backend.
///
/// The backend owns all discovery, ranking and travel-time logic; this model is
/// a dumb render target. Field names mirror the API (`/api/v1/experiences`,
/// `/api/v1/places/search`, `POST /api/v1/recommend`).
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    this.area = '',
    this.avgCost = 0,
    this.durationMin = 60,
    this.openTime = '09:00',
    this.closeTime = '21:00',
    this.rating = 0.0,
    this.reviewCount = 0,
    this.description = '',
    this.imageUrl,
    this.tags = const <String>[],
    this.accessibilityFlags = const <String>[],
    this.indoorOutdoor = IndoorOutdoor.indoor,
    this.localGemScore = 0.5,
    this.distanceKm,
    this.travelMinutes,
    this.isOpenNow,
  });

  final String id;
  final String name;
  final PlaceCategory category;
  final double lat;
  final double lng;
  final String area;
  final int avgCost;
  final int durationMin;
  final String openTime;
  final String closeTime;
  final double rating;
  final int reviewCount;
  final String description;

  /// Photo URL. Either the curated dataset value or a LocalIQ photo-proxy URL
  /// (`/api/v1/images/place?...`) — never a raw Google URL with a key.
  final String? imageUrl;

  final List<String> tags;
  final List<String> accessibilityFlags;
  final IndoorOutdoor indoorOutdoor;
  final double localGemScore;

  /// Backend-computed values (present on search/detail/recommend responses).
  final double? distanceKm;
  final int? travelMinutes;
  final bool? isOpenNow;

  /// Distance for display. Prefers the backend value; when running on offline
  /// mock data there is none, so the client falls back to the same Haversine
  /// heuristic the backend uses.
  double distanceFrom(double lat, double lng) =>
      distanceKm ?? Geo.haversineKm(lat, lng, this.lat, this.lng);

  /// Travel minutes for display (see [distanceFrom]).
  int travelFrom(double lat, double lng) =>
      travelMinutes ?? Geo.travelMinutes(distanceFrom(lat, lng));

  /// Label for display, e.g. 'Food'.
  String get categoryLabel => category.label;

  String get blurb => tags.isEmpty ? categoryLabel : tags.take(2).join(' · ');

  bool get isWheelchairFriendly =>
      accessibilityFlags.any((String f) => f.contains('wheelchair'));

  bool get isStepFree =>
      accessibilityFlags.any((String f) => f.contains('step-free'));

  /// Fallback opening-hours check, used only when the backend did not send
  /// `is_open` (i.e. older cached responses).
  bool get openNow {
    final bool? fromApi = isOpenNow;
    if (fromApi != null) return fromApi;
    return isOpenAt(DateTime.now());
  }

  bool isOpenAt(DateTime time) {
    final int? open = _minutesOfDay(openTime);
    final int? close = _minutesOfDay(closeTime);
    if (open == null || close == null) return true;
    if (open == 0 && close == 0) return true;
    final int now = time.hour * 60 + time.minute;
    if (close > open) return now >= open && now <= close;
    // Overnight venue, e.g. 18:00 - 01:30.
    return now >= open || now <= close;
  }

  static int? _minutesOfDay(String value) {
    final List<String> parts = value.split(':');
    if (parts.length < 2) return null;
    final int? h = int.tryParse(parts[0]);
    final int? m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// Builds a place from the flat recommendation item returned by
  /// `POST /api/v1/recommend` (already frontend-ready).
  factory Place.fromRecommendation(Map<String, dynamic> json) {
    final Map<String, dynamic> hours =
        (json['opening_hours'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final Map<String, dynamic> route =
        (json['route'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return Place(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? 'Unknown place'}',
      category: PlaceCategory.fromLabel('${json['category'] ?? 'culture'}'),
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      area: '${json['area'] ?? ''}',
      avgCost: (json['cost'] as num?)?.round() ?? 0,
      durationMin: (json['duration_min'] as num?)?.round() ?? 0,
      openTime: '${hours['open_time'] ?? '09:00'}',
      closeTime: '${hours['close_time'] ?? '21:00'}',
      isOpenNow: hours['is_open'] as bool?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.round() ?? 0,
      description: '${json['description'] ?? ''}',
      imageUrl: json['image'] as String? ?? json['image_url'] as String?,
      tags: _stringList(json['tags']),
      accessibilityFlags: _stringList(json['accessibility_flags']),
      indoorOutdoor: IndoorOutdoor.fromLabel('${json['indoor_outdoor'] ?? 'indoor'}'),
      localGemScore: (json['local_gem_score'] as num?)?.toDouble() ?? 0.5,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      travelMinutes: (route['duration_min'] as num?)?.round() ??
          (json['travel_time_min'] as num?)?.round(),
    );
  }

  /// Builds a place from `GET /api/v1/experiences/{id}`.
  factory Place.fromDetail(Map<String, dynamic> json) {
    final Map<String, dynamic> exp =
        (json['experience'] as Map<String, dynamic>?) ?? json;
    return Place(
      id: '${exp['id'] ?? ''}',
      name: '${exp['name'] ?? 'Unknown place'}',
      category: PlaceCategory.fromLabel('${exp['category'] ?? 'culture'}'),
      lat: (exp['lat'] as num?)?.toDouble() ?? 0,
      lng: (exp['lng'] as num?)?.toDouble() ?? 0,
      avgCost: (exp['avg_cost'] as num?)?.round() ?? 0,
      durationMin: (exp['duration_min'] as num?)?.round() ?? 60,
      openTime: '${exp['open_time'] ?? '09:00'}',
      closeTime: '${exp['close_time'] ?? '21:00'}',
      rating: (exp['rating'] as num?)?.toDouble() ?? 0,
      description: '${exp['description'] ?? ''}',
      imageUrl: exp['image_url'] as String?,
      tags: _stringList(exp['tags']),
      accessibilityFlags: _stringList(exp['accessibility_flags']),
      indoorOutdoor: IndoorOutdoor.fromLabel('${exp['indoor_outdoor'] ?? 'indoor'}'),
      localGemScore: (exp['local_gem_score'] as num?)?.toDouble() ?? 0.5,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      travelMinutes: (json['travel_time_min'] as num?)?.round(),
      isOpenNow:
          (json['opening_hours'] as Map<String, dynamic>?)?['is_open'] as bool?,
    );
  }

  /// Builds a place from `GET /api/v1/places/search` (Google or SQLite).
  factory Place.fromPlaceSearch(Map<String, dynamic> json) {
    return Place(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? 'Unknown place'}',
      category: PlaceCategory.fromLabel('${json['category'] ?? 'culture'}'),
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      area: '${json['address'] ?? ''}',
      avgCost: (json['avg_cost'] as num?)?.round() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.round() ?? 0,
      description: '${json['description'] ?? ''}',
      imageUrl: json['image_url'] as String?,
      openTime: '${json['open_time'] ?? '09:00'}',
      closeTime: '${json['close_time'] ?? '21:00'}',
      isOpenNow: json['open_now'] as bool?,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      travelMinutes: (json['travel_minutes'] as num?)?.round(),
    );
  }

  /// Builds a place from the legacy nested `experience` object.
  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? 'Unknown place'}',
      category: PlaceCategory.fromLabel('${json['category'] ?? 'culture'}'),
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      avgCost: (json['avg_cost'] as num?)?.round() ?? 0,
      durationMin: (json['duration_min'] as num?)?.round() ?? 60,
      openTime: '${json['open_time'] ?? '09:00'}',
      closeTime: '${json['close_time'] ?? '21:00'}',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      description: '${json['description'] ?? ''}',
      imageUrl: json['image_url'] as String?,
      tags: _stringList(json['tags']),
      accessibilityFlags: _stringList(json['accessibility_flags']),
      indoorOutdoor: IndoorOutdoor.fromLabel('${json['indoor_outdoor'] ?? 'indoor'}'),
      localGemScore: (json['local_gem_score'] as num?)?.toDouble() ?? 0.5,
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value.map((dynamic e) => '$e').toList();
  }

  /// Returns a copy carrying backend-computed distance/travel values.
  Place copyWithDistance({double? distanceKm, int? travelMinutes}) {
    return Place(
      id: id,
      name: name,
      category: category,
      lat: lat,
      lng: lng,
      area: area,
      avgCost: avgCost,
      durationMin: durationMin,
      openTime: openTime,
      closeTime: closeTime,
      rating: rating,
      reviewCount: reviewCount,
      description: description,
      imageUrl: imageUrl,
      tags: tags,
      accessibilityFlags: accessibilityFlags,
      indoorOutdoor: indoorOutdoor,
      localGemScore: localGemScore,
      distanceKm: distanceKm ?? this.distanceKm,
      travelMinutes: travelMinutes ?? this.travelMinutes,
      isOpenNow: isOpenNow,
    );
  }

  @override
  bool operator ==(Object other) => other is Place && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum PlaceCategory {
  food('Food', Icons.restaurant_rounded),
  culture('Culture', Icons.account_balance_rounded),
  shopping('Shopping', Icons.shopping_bag_rounded),
  art('Art', Icons.palette_rounded),
  nightlife('Nightlife', Icons.nightlife_rounded),
  outdoor('Outdoors', Icons.park_rounded);

  const PlaceCategory(this.label, this.icon);

  final String label;
  final IconData icon;

  static PlaceCategory fromLabel(String value) {
    return PlaceCategory.values.firstWhere(
      (PlaceCategory c) => c.name == value.toLowerCase(),
      orElse: () => PlaceCategory.culture,
    );
  }
}

enum IndoorOutdoor {
  indoor('Indoor', Icons.home_rounded),
  outdoor('Outdoor', Icons.wb_sunny_rounded),
  mixed('Indoor + Outdoor', Icons.filter_hdr_rounded);

  const IndoorOutdoor(this.label, this.icon);

  final String label;
  final IconData icon;

  static IndoorOutdoor fromLabel(String value) {
    return IndoorOutdoor.values.firstWhere(
      (IndoorOutdoor v) => v.name == value.toLowerCase(),
      orElse: () => IndoorOutdoor.indoor,
    );
  }
}

enum GroupType {
  solo('Solo', Icons.person_rounded),
  friends('Friends', Icons.group_rounded),
  family('Family', Icons.family_restroom_rounded),
  couple('Couple', Icons.favorite_rounded);

  const GroupType(this.label, this.icon);

  final String label;
  final IconData icon;

  static GroupType fromLabel(String value) {
    return GroupType.values.firstWhere(
      (GroupType g) => g.name == value.toLowerCase(),
      orElse: () => GroupType.friends,
    );
  }
}
