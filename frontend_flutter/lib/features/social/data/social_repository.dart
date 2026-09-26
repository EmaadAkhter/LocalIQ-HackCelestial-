import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/social.dart';
import 'local_social.dart';

abstract class SocialRepository {
  Future<List<PeopleMatch>> getMatches();
  Future<PeopleMatch?> getMatchByUserId(String userId);
}

class LocalSocialRepository implements SocialRepository {
  const LocalSocialRepository();

  @override
  Future<List<PeopleMatch>> getMatches() async {
    return kLocalPeopleMatches;
  }

  @override
  Future<PeopleMatch?> getMatchByUserId(String userId) async {
    return kLocalPeopleMatches.cast<PeopleMatch?>().firstWhere(
          (m) => m?.userId == userId,
          orElse: () => null,
        );
  }
}

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  return const LocalSocialRepository();
}, name: 'localiq.socialRepository');

final peopleMatchesProvider = FutureProvider<List<PeopleMatch>>((ref) async {
  final repo = ref.watch(socialRepositoryProvider);
  return repo.getMatches();
}, name: 'localiq.peopleMatches');
