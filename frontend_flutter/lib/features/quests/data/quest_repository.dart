import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/quest.dart';
import 'local_quests.dart';

abstract class QuestRepository {
  Future<List<Quest>> getQuests();
  Future<Quest?> getQuestById(String id);
}

class LocalQuestRepository implements QuestRepository {
  const LocalQuestRepository();

  @override
  Future<List<Quest>> getQuests() async {
    return kLocalQuests;
  }

  @override
  Future<Quest?> getQuestById(String id) async {
    return kLocalQuests.cast<Quest?>().firstWhere(
          (q) => q?.id == id,
          orElse: () => null,
        );
  }
}

final questRepositoryProvider = Provider<QuestRepository>((ref) {
  return const LocalQuestRepository();
}, name: 'localiq.questRepository');

final allQuestsProvider = FutureProvider<List<Quest>>((ref) async {
  final repo = ref.watch(questRepositoryProvider);
  return repo.getQuests();
}, name: 'localiq.allQuests');

final questByIdProvider = Provider.family<Quest?, String>((ref, id) {
  final list = ref.watch(allQuestsProvider).value ?? kLocalQuests;
  return list.cast<Quest?>().firstWhere(
        (q) => q?.id == id,
        orElse: () => null,
      );
}, name: 'localiq.questById');
