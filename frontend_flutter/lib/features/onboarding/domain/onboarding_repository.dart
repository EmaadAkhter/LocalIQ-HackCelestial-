import 'onboarding.dart';

/// The guided taste conversation.
abstract interface class OnboardingRepository {
  Future<OnboardingStep> start({bool restart = false});

  Future<OnboardingStep> answer(
    int sessionId, {
    String? message,
    List<String> selections = const [],
  });

  Future<OnboardingStep> status();
}
