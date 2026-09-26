import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../recommendations/domain/recommendation.dart';
import '../../recommendations/application/recommendation_controller.dart';

/// Saved experiences, kept in sync with the repository.
class SavedController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    return ref.watch(savedRepositoryProvider).load();
  }

  Future<void> toggle(Recommendation recommendation) async {
    final repo = ref.watch(savedRepositoryProvider);
    final current = state.value ?? const <String>{};
    final next = {...current};
    final isRemoving = next.remove(recommendation.experience.id);
    if (!isRemoving) {
      next.add(recommendation.experience.id);
      await repo.add(recommendation.experience.id);
    } else {
      await repo.remove(recommendation.experience.id);
    }
    state = AsyncData(next);
  }

  Future<void> remove(String experienceId) async {
    final current = state.value ?? const <String>{};
    if (!current.contains(experienceId)) return;
    await ref.watch(savedRepositoryProvider).remove(experienceId);
    state = AsyncData({...current}..remove(experienceId));
  }

  Future<void> clear() async {
    await ref.watch(savedRepositoryProvider).clear();
    state = const AsyncData(<String>{});
  }
}

final savedControllerProvider =
    AsyncNotifierProvider<SavedController, Set<String>>(
  SavedController.new,
  name: 'localiq.saved',
);

final isSavedProvider = Provider.family<bool, String>((ref, id) {
  return ref.watch(savedControllerProvider).value?.contains(id) ?? false;
});

final savedCountProvider = Provider<int>((ref) {
  return ref.watch(savedControllerProvider).value?.length ?? 0;
});

/// Saved options, resolved to live recommendations so feasibility stays
/// accurate even after the constraints change.
final savedRecommendationsProvider = Provider<List<Recommendation>>((ref) {
  final ids = ref.watch(savedControllerProvider).value ?? const <String>{};
  final result = ref.watch(recommendationControllerProvider).value;
  if (result == null) return const [];
  final out = <Recommendation>[];
  for (final id in ids) {
    final match = result.byId(id);
    if (match != null) out.add(match);
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
});

/// Saved entries whose place could not be resolved against the live result.
final savedOrphanIdsProvider = Provider<Set<String>>((ref) {
  final ids = ref.watch(savedControllerProvider).value ?? const <String>{};
  final result = ref.watch(recommendationControllerProvider).value;
  if (result == null) return ids;
  return {
    for (final id in ids)
      if (result.byId(id) == null) id,
  };
});
