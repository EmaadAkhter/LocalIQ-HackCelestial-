import '../../context/domain/context_models.dart';
import '../../context/domain/discovery_context.dart';
import '../../places/domain/place.dart';
import 'recommendation.dart';

/// Input to the recommendation engine. Everything the engine needs is here,
/// so it stays a pure function and is trivially testable.
class RecommendationRequest {
  const RecommendationRequest({
    required this.context,
    required this.weather,
    required this.traffic,
    required this.candidates,
    required this.excludedExperienceIds,
    this.query,
    this.limit = 30,
  });

  final DiscoveryContext context;
  final WeatherSnapshot weather;
  final TrafficSnapshot traffic;

  /// Place + experience pairs to evaluate.
  final List<({Place place, Experience experience})> candidates;

  /// Already in the user's plan, down-weighted rather than hidden.
  final Set<String> excludedExperienceIds;

  final String? query;
  final int limit;
}

/// The full, ordered output of the engine.
class RecommendationResult {
  const RecommendationResult({
    required this.recommendations,
    required this.evaluatedCount,
    required this.context,
    required this.generatedAt,
  });

  final List<Recommendation> recommendations;
  final int evaluatedCount;
  final DiscoveryContext context;
  final DateTime generatedAt;

  List<Recommendation> get feasible =>
      recommendations.where((r) => r.tier == FeasibilityTier.feasible).toList();

  List<Recommendation> get partial => recommendations
      .where((r) => r.tier == FeasibilityTier.partial)
      .toList();

  List<Recommendation> get blocked => recommendations
      .where((r) => r.tier == FeasibilityTier.notFeasible)
      .toList();

  int get feasibleCount => feasible.length;
  int get partialCount => partial.length;
  int get blockedCount => blocked.length;

  bool get isEmpty => recommendations.isEmpty;

  /// Aggregate view across all three tiers, ordered by tier then score.
  List<Recommendation> get byTier {
    return [...feasible, ...partial, ...blocked];
  }

  Recommendation? byId(String id) {
    for (final r in recommendations) {
      if (r.experience.id == id) return r;
    }
    return null;
  }
}

/// Scoring + feasibility engine.
///
/// The contract is deliberately server-shaped: a backend implementation can
/// replace the local one by POSTing [RecommendationRequest] and decoding a
/// [RecommendationResult] — the UI does not change.
abstract interface class RecommendationEngine {
  Future<RecommendationResult> recommend(RecommendationRequest request);

  /// Resolves travel time from the origin to a place under live traffic.
  Future<TravelEstimate> estimateTravel({
    required LatLng from,
    required Place place,
    required TrafficSnapshot traffic,
  });
}
