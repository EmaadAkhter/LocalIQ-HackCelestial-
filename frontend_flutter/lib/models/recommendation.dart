import 'place.dart';

/// A ranked, feasible place returned by `POST /api/v1/recommend`.
///
/// The backend already applied feasibility + ranking and returned every value
/// the UI needs, so this class only carries data — there is no scoring, no
/// distance maths and no filtering here.
class Recommendation {
  const Recommendation({
    required this.place,
    required this.score,
    required this.distanceKm,
    required this.travelMinutes,
    required this.totalMinutes,
    required this.estimatedCost,
    required this.whyItFits,
    required this.reasons,
    this.routeSource = 'local',
    this.polyline,
  });

  final Place place;

  /// Backend relevance score (higher is better).
  final double score;

  final double distanceKm;

  /// One-way travel time computed by the backend (Google Routes when available).
  final int travelMinutes;

  /// Visit + return travel + buffer, as computed by the backend.
  final int totalMinutes;

  final int estimatedCost;

  /// One-line summary, e.g. "Fits your ₹800 budget · …".
  final String whyItFits;

  /// Bullet reasons shown on Place Details.
  final List<String> reasons;

  /// 'google_routes' when the backend used the Routes API, else 'local'.
  final String routeSource;

  /// Encoded polyline for drawing the route, when the backend provided one.
  final String? polyline;

  factory Recommendation.fromApiJson(Map<String, dynamic> json) {
    final Map<String, dynamic> route =
        (json['route'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return Recommendation(
      place: Place.fromRecommendation(json),
      score: (json['score'] as num?)?.toDouble() ?? 0,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      travelMinutes: (json['travel_time_min'] as num?)?.round() ?? 0,
      totalMinutes: (json['total_time_min'] as num?)?.round() ?? 0,
      estimatedCost: (json['cost'] as num?)?.round() ?? 0,
      whyItFits: '${json['why_this_fits'] ?? ''}',
      reasons: (json['reasons'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(),
      routeSource: '${route['source'] ?? 'local'}',
      polyline: route['polyline'] as String?,
    );
  }
}

/// Aggregate metadata for the recommendations screen.
class RecommendationResult {
  const RecommendationResult({
    required this.items,
    required this.totalCandidates,
    this.weatherSummary,
    this.routeSource = 'local',
    this.usedFallback = false,
  });

  final List<Recommendation> items;
  final int totalCandidates;
  final String? weatherSummary;

  /// 'google_routes' or 'local' — surfaced in the UI as a small badge.
  final String routeSource;

  /// True when the backend answered from SQLite/Haversine instead of Google.
  final bool usedFallback;
}
