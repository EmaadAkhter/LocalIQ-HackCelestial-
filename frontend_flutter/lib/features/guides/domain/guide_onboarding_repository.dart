import 'guide_onboarding.dart';

/// Fast guide onboarding: create the application, upload licences, choose the
/// areas and niches the guide covers, then submit for review.
abstract interface class GuideOnboardingRepository {
  Future<GuideOptions> options();

  Future<GuideOnboardingStatus> start({
    String? name,
    List<String> languages = const [],
    String city = 'Mumbai',
    String bio = '',
  });

  Future<GuideDocument> uploadDocument({
    required String kind,
    required List<int> bytes,
    required String filename,
    String contentType = 'image/png',
  });

  Future<GuideOnboardingStatus> apply({
    required List<String> areas,
    required List<String> niches,
    int? ratePerHour,
    String? bio,
    List<String> languages = const [],
  });

  Future<GuideOnboardingStatus> status();
}
