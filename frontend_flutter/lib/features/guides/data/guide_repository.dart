import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/guide.dart';
import 'local_guides.dart';

abstract class GuideRepository {
  Future<List<Guide>> getGuides();
  Future<Guide?> getGuideById(String id);
}

class LocalGuideRepository implements GuideRepository {
  const LocalGuideRepository();

  @override
  Future<List<Guide>> getGuides() async {
    return kLocalGuides;
  }

  @override
  Future<Guide?> getGuideById(String id) async {
    return kLocalGuides.cast<Guide?>().firstWhere(
          (g) => g?.id == id,
          orElse: () => null,
        );
  }
}

final guideRepositoryProvider = Provider<GuideRepository>((ref) {
  return const LocalGuideRepository();
}, name: 'localiq.guideRepository');

final allGuidesProvider = FutureProvider<List<Guide>>((ref) async {
  final repo = ref.watch(guideRepositoryProvider);
  return repo.getGuides();
}, name: 'localiq.allGuides');

final guideByIdProvider = Provider.family<Guide?, String>((ref, id) {
  final list = ref.watch(allGuidesProvider).value ?? kLocalGuides;
  return list.cast<Guide?>().firstWhere(
        (g) => g?.id == id,
        orElse: () => null,
      );
}, name: 'localiq.guideById');
