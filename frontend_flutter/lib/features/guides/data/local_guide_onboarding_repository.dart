import '../domain/guide_onboarding.dart';
import '../domain/guide_onboarding_repository.dart';

/// Offline [GuideOnboardingRepository]: an in-memory application so the flow is
/// fully explorable without a backend (and testable).
class LocalGuideOnboardingRepository implements GuideOnboardingRepository {
  bool _started = false;
  final _documents = <String, GuideDocument>{};
  List<String> _areas = const [];
  List<String> _niches = const [];

  @override
  Future<GuideOptions> options() async => const GuideOptions(
        areas: [
          'Andheri', 'Bandra', 'Borivali', 'Chembur', 'Colaba', 'Dadar',
          'Fort', 'Juhu', 'Powai', 'Thane', 'Worli', 'Navi Mumbai',
        ],
        niches: [
          'street_food', 'food', 'heritage', 'culture', 'art', 'history',
          'nightlife', 'shopping', 'nature', 'adventure', 'photography',
          'wellness',
        ],
      );

  @override
  Future<GuideOnboardingStatus> start({
    String? name,
    List<String> languages = const [],
    String city = 'Mumbai',
    String bio = '',
  }) async {
    _started = true;
    return _status();
  }

  @override
  Future<GuideDocument> uploadDocument({
    required String kind,
    required List<int> bytes,
    required String filename,
    String contentType = 'image/png',
  }) async {
    _started = true;
    final document = GuideDocument(
      kind: kind,
      key: 'guides/local/$kind-${bytes.length}.png',
      contentType: contentType,
      size: bytes.length,
    );
    _documents[kind] = document;
    return document;
  }

  @override
  Future<GuideOnboardingStatus> apply({
    required List<String> areas,
    required List<String> niches,
    int? ratePerHour,
    String? bio,
    List<String> languages = const [],
  }) async {
    if (_documents['driver_license'] == null || _documents['guide_license'] == null) {
      throw StateError('both licences are required');
    }
    if (areas.isEmpty) throw StateError('select at least one area');
    _areas = areas;
    _niches = niches;
    return _status(submitted: true);
  }

  @override
  Future<GuideOnboardingStatus> status() async => _status();

  GuideOnboardingStatus _status({bool submitted = false}) => GuideOnboardingStatus(
        guideId: _started ? 1 : null,
        state: _started ? (submitted ? 'id_uploaded' : 'signup') : 'not_started',
        verificationStatus: submitted ? 'pending' : 'unverified',
        documents: {for (final e in _documents.entries) e.key: {'key': e.value.key}},
        hasDriverLicense: _documents.containsKey('driver_license'),
        hasGuideLicense: _documents.containsKey('guide_license'),
        areas: _areas,
        niches: _niches,
        canSubmit: _documents.containsKey('driver_license') &&
            _documents.containsKey('guide_license'),
        submittedAt: submitted ? DateTime.now().toIso8601String() : null,
      );
}
