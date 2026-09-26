import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/providers.dart';
import '../data/local_onboarding_repository.dart';
import '../data/remote_onboarding_repository.dart';
import '../domain/onboarding_repository.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return ref.watch(remoteDataEnabledProvider)
      ? RemoteOnboardingRepository(ref.watch(apiClientProvider))
      : LocalOnboardingRepository();
}, name: 'localiq.onboardingRepository');
