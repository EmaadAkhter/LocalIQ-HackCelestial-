import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../context/application/discovery_context_controller.dart';
import '../../../core/providers.dart';
import '../../places/domain/place.dart';
import '../domain/recommendation.dart';
import '../domain/recommendation_engine.dart';

/// Runs the feasibility engine whenever any constraint, the weather, the
/// traffic or the plan changes. The result is the ranked list the UI renders.
class RecommendationController
    extends AsyncNotifier<RecommendationResult> {
  @override
  Future<RecommendationResult> build() async {
    final context = ref.watch(discoveryContextProvider);
    final live = await ref.watch(liveContextProvider.future);
    final places = await ref.watch(allPlacesProvider.future);
    final experiences = await ref.watch(allExperiencesProvider.future);
    final engine = ref.watch(recommendationEngineProvider);
    final plannedIds = ref.watch(plannedExperienceIdsProvider);

    final byPlace = <String, Place>{
      for (final place in places) place.id: place,
    };
    final candidates = <({Place place, Experience experience})>[];
    for (final experience in experiences) {
      final place = byPlace[experience.placeId];
      if (place != null) candidates.add((place: place, experience: experience));
    }

    return engine.recommend(
      RecommendationRequest(
        context: context,
        weather: live.weather,
        traffic: live.traffic,
        candidates: candidates,
        excludedExperienceIds: plannedIds,
        query: context.query,
        limit: 40,
      ),
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue<RecommendationResult>.loading();
    state = await AsyncValue.guard(build);
  }
}

final recommendationControllerProvider =
    AsyncNotifierProvider<RecommendationController, RecommendationResult>(
  RecommendationController.new,
  name: 'localiq.recommendations',
);

/// Convenience selector: only the achievable options, in rank order.
final feasibleRecommendationsProvider = Provider<List<Recommendation>>((ref) {
  final result = ref.watch(recommendationControllerProvider).value;
  return result?.feasible ?? const [];
});

final partialRecommendationsProvider = Provider<List<Recommendation>>((ref) {
  final result = ref.watch(recommendationControllerProvider).value;
  return result?.partial ?? const [];
});

final blockedRecommendationsProvider = Provider<List<Recommendation>>((ref) {
  final result = ref.watch(recommendationControllerProvider).value;
  return result?.blocked ?? const [];
});

/// One recommendation by experience id, for detail pages and deep links.
final recommendationByIdProvider =
    Provider.family<Recommendation?, String>((ref, id) {
  final result = ref.watch(recommendationControllerProvider).value;
  return result?.byId(id);
});

/// Counts used by the header pills.
final recommendationCountsProvider =
    Provider<({int total, int feasible, int partial, int blocked})>((ref) {
  final result = ref.watch(recommendationControllerProvider).value;
  if (result == null) {
    return (total: 0, feasible: 0, partial: 0, blocked: 0);
  }
  return (
    total: result.evaluatedCount,
    feasible: result.feasibleCount,
    partial: result.partialCount,
    blocked: result.blockedCount,
  );
});

/// Filled by the itinerary controller so the engine can de-prioritise options
/// that are already in the plan without removing them.
final plannedExperienceIdsProvider = Provider<Set<String>>((ref) => const {});
