import '../../../core/utils/json_map_x.dart';

/// Areas, niches and the document kinds the backend expects.
class GuideOptions {
  const GuideOptions({
    this.areas = const [],
    this.niches = const [],
    this.documentKinds = const ['driver_license', 'guide_license'],
  });

  final List<String> areas;
  final List<String> niches;
  final List<String> documentKinds;

  factory GuideOptions.fromJson(Map<String, dynamic> json) => GuideOptions(
        areas: json.stringList('areas'),
        niches: json.stringList('niches'),
        documentKinds: json.stringList('documentKinds').isEmpty
            ? const ['driver_license', 'guide_license']
            : json.stringList('documentKinds'),
      );
}

/// The guide's application state.
class GuideOnboardingStatus {
  const GuideOnboardingStatus({
    this.guideId,
    this.state = 'not_started',
    this.verificationStatus = 'unverified',
    this.verificationTier = 'basic',
    this.requiredDocuments = const ['driver_license', 'guide_license'],
    this.documents = const {},
    this.hasDriverLicense = false,
    this.hasGuideLicense = false,
    this.areas = const [],
    this.niches = const [],
    this.canSubmit = false,
    this.isPublished = false,
    this.submittedAt,
    this.adminNotes,
  });

  final int? guideId;
  final String state;
  final String verificationStatus;
  final String verificationTier;
  final List<String> requiredDocuments;
  final Map<String, dynamic> documents;
  final bool hasDriverLicense;
  final bool hasGuideLicense;
  final List<String> areas;
  final List<String> niches;
  final bool canSubmit;
  final bool isPublished;
  final String? submittedAt;
  final String? adminNotes;

  bool get started => state != 'not_started';
  bool get isPending => verificationStatus == 'pending';
  bool get isVerified => verificationStatus == 'verified';
  bool get isRejected => verificationStatus == 'rejected';

  String get verificationLabel => switch (verificationStatus) {
        'pending' => 'Under review',
        'verified' => 'Verified guide',
        'rejected' => 'Needs attention',
        _ => 'Not started',
      };

  factory GuideOnboardingStatus.fromJson(Map<String, dynamic> json) {
    final docs = json.pick('documents');
    return GuideOnboardingStatus(
      guideId: json.intOrNull('guideId'),
      state: json.string('state') ?? 'not_started',
      verificationStatus: json.string('verificationStatus') ?? 'unverified',
      verificationTier: json.string('verificationTier') ?? 'basic',
      requiredDocuments: json.stringList('requiredDocuments').isEmpty
          ? const ['driver_license', 'guide_license']
          : json.stringList('requiredDocuments'),
      documents: docs is Map ? docs.cast<String, dynamic>() : const {},
      hasDriverLicense: json.boolValue('hasDriverLicense'),
      hasGuideLicense: json.boolValue('hasGuideLicense'),
      areas: json.stringList('areas'),
      niches: json.stringList('niches'),
      canSubmit: json.boolValue('canSubmit'),
      isPublished: json.boolValue('isPublished'),
      submittedAt: json.stringOrNull('submittedAt'),
      adminNotes: json.stringOrNull('adminNotes'),
    );
  }
}

/// A licence the guide has uploaded.
class GuideDocument {
  const GuideDocument({
    required this.kind,
    required this.key,
    required this.contentType,
    required this.size,
  });

  final String kind;
  final String key;
  final String contentType;
  final int size;

  factory GuideDocument.fromJson(Map<String, dynamic> json) => GuideDocument(
        kind: json.string('kind') ?? '',
        key: json.string('key') ?? '',
        contentType: json.string('contentType') ?? '',
        size: json.intValue('size'),
      );
}
