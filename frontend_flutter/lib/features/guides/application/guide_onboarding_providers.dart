import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/local_guide_onboarding_repository.dart';
import '../data/remote_guide_onboarding_repository.dart';
import '../domain/guide_onboarding.dart';
import '../domain/guide_onboarding_repository.dart';

final guideOnboardingRepositoryProvider =
    Provider<GuideOnboardingRepository>((ref) {
  return ref.watch(remoteDataEnabledProvider)
      ? RemoteGuideOnboardingRepository(ref.watch(apiClientProvider))
      : LocalGuideOnboardingRepository();
}, name: 'localiq.guideOnboardingRepository');

/// Areas, niches and required documents.
final guideOptionsProvider = FutureProvider<GuideOptions>((ref) async {
  return ref.watch(guideOnboardingRepositoryProvider).options();
}, name: 'localiq.guideOptions');

/// The current application state.
final guideOnboardingStatusProvider =
    FutureProvider<GuideOnboardingStatus>((ref) async {
  return ref.watch(guideOnboardingRepositoryProvider).status();
}, name: 'localiq.guideOnboardingStatus');
