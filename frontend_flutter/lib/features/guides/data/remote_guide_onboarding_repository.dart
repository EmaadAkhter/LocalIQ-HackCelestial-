import '../../../core/network/json_api_client.dart';
import '../domain/guide_onboarding.dart';
import '../domain/guide_onboarding_repository.dart';

/// REST implementation of [GuideOnboardingRepository].
///
///   GET  /guides/onboarding/options
///   POST /guides/onboarding/start
///   POST /guides/onboarding/documents   (multipart)
///   POST /guides/onboarding/apply
///   GET  /guides/onboarding/me
class RemoteGuideOnboardingRepository implements GuideOnboardingRepository {
  RemoteGuideOnboardingRepository(this._client);

  final JsonApiClient _client;

  @override
  Future<GuideOptions> options() async {
    final data = await _client.get('/guides/onboarding/options');
    return GuideOptions.fromJson((data as Map).cast<String, dynamic>());
  }

  @override
  Future<GuideOnboardingStatus> start({
    String? name,
    List<String> languages = const [],
    String city = 'Mumbai',
    String bio = '',
  }) async {
    final data = await _client.post('/guides/onboarding/start', body: {
      'name': ?name,
      'languages': languages,
      'city': city,
      'bio': bio,
    });
    return GuideOnboardingStatus.fromJson((data as Map).cast<String, dynamic>());
  }

  @override
  Future<GuideDocument> uploadDocument({
    required String kind,
    required List<int> bytes,
    required String filename,
    String contentType = 'image/png',
  }) async {
    final data = await _client.postMultipart(
      '/guides/onboarding/documents',
      fileField: 'file',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      fields: {'kind': kind},
    );
    return GuideDocument.fromJson((data as Map).cast<String, dynamic>());
  }

  @override
  Future<GuideOnboardingStatus> apply({
    required List<String> areas,
    required List<String> niches,
    int? ratePerHour,
    String? bio,
    List<String> languages = const [],
  }) async {
    final data = await _client.post('/guides/onboarding/apply', body: {
      'areas': areas,
      'niches': niches,
      'rate_per_hour': ?ratePerHour,
      'bio': ?bio,
      'languages': languages,
    });
    return GuideOnboardingStatus.fromJson((data as Map).cast<String, dynamic>());
  }

  @override
  Future<GuideOnboardingStatus> status() async {
    final data = await _client.get('/guides/onboarding/me');
    return GuideOnboardingStatus.fromJson((data as Map).cast<String, dynamic>());
  }
}
