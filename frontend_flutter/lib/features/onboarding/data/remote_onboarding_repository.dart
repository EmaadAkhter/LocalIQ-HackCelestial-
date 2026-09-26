import '../../../core/network/json_api_client.dart';
import '../domain/onboarding.dart';
import '../domain/onboarding_repository.dart';

/// REST implementation of [OnboardingRepository].
///
///   POST /onboarding/user/start
///   POST /onboarding/user/{id}/answer  { message, selections }
///   GET  /onboarding/user/status
class RemoteOnboardingRepository implements OnboardingRepository {
  RemoteOnboardingRepository(this._client);

  final JsonApiClient _client;

  @override
  Future<OnboardingStep> start({bool restart = false}) async {
    final data = await _client.post(
      '/onboarding/user/start',
      body: {'restart': restart},
    );
    return OnboardingStep.fromJson((data as Map).cast<String, dynamic>());
  }

  @override
  Future<OnboardingStep> answer(
    int sessionId, {
    String? message,
    List<String> selections = const [],
  }) async {
    final data = await _client.post(
      '/onboarding/user/$sessionId/answer',
      body: {'message': message, 'selections': selections},
    );
    return OnboardingStep.fromJson((data as Map).cast<String, dynamic>());
  }

  @override
  Future<OnboardingStep> status() async {
    final data = await _client.get('/onboarding/user/status');
    return OnboardingStep.fromJson((data as Map).cast<String, dynamic>());
  }
}
