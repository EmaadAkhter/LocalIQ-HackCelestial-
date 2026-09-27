/// Build-time environment configuration.
///
/// Values are injected with `--dart-define`, so no key or endpoint is ever
/// committed to the repository. [Environment.fromEnvironment] is the single
/// source of truth; nothing else in the app reads `String.fromEnvironment`.
library;

import 'package:flutter/foundation.dart';

enum LocalIqEnvironment { dev, staging, prod }

extension LocalIqEnvironmentX on LocalIqEnvironment {
  String get label => switch (this) {
        LocalIqEnvironment.dev => 'Development',
        LocalIqEnvironment.staging => 'Staging',
        LocalIqEnvironment.prod => 'Production',
      };

  /// Default base URL per environment.
  ///
  /// The paths track the FastAPI backend in `../backend`, which mounts its
  /// routers under `/api/v1`. Note that flipping to the remote data source is
  /// **not** sufficient on its own — see `docs/BACKEND_CONTRACT.md` for the
  /// endpoint-by-endpoint gap.
  String get apiBaseUrl => switch (this) {
        // On web/desktop, talk to localhost.
        // On Android EMULATOR, 10.0.2.2 maps to the host machine.
        // On a PHYSICAL device, set --dart-define=LOCALIQ_API_BASE_URL=http://<your-machine-ip>:8000/api/v1
        LocalIqEnvironment.dev =>
          kIsWeb ? 'http://localhost:8000/api/v1' : 'http://192.168.0.101:8000/api/v1',
        LocalIqEnvironment.staging => 'https://staging-api.localiq.app/api/v1',
        LocalIqEnvironment.prod => 'https://api.localiq.app/api/v1',
      };

  Duration get timeout => switch (this) {
        LocalIqEnvironment.dev => const Duration(seconds: 20),
        _ => const Duration(seconds: 30),
      };
}

@immutable
class Environment {
  const Environment({
    required this.name,
    required this.apiBaseUrlOverride,
    required this.apiKeyOverride,
    required this.googleMapsApiKey,
    required this.googlePlacesApiKey,
    required this.googleServerClientId,
    required this.useOfflineData,
    required this.requestTimeout,
    required this.aiAssistantEnabled,
  });

  final LocalIqEnvironment name;

  /// Backend base URL. Null means "talk to the offline data source".
  final String? apiBaseUrlOverride;

  /// Static API token for first-party backend calls. In production this should
  /// be replaced by short-lived tokens issued by the auth backend.
  final String? apiKeyOverride;

  final String? googleMapsApiKey;
  final String? googlePlacesApiKey;

  /// The **web** OAuth client id used for Google Sign-In.
  ///
  /// Android must pass this as `serverClientId`; Google then mints an idToken
  /// whose audience is the web client, which is exactly what the backend
  /// validates against `GOOGLE_OAUTH_CLIENT_ID`. Using the Android client id
  /// here would produce a token the backend rejects.
  final String? googleServerClientId;

  /// When true the app never touches the network.
  final bool useOfflineData;
  final Duration requestTimeout;
  final bool aiAssistantEnabled;

  bool get hasBackend =>
      apiBaseUrlOverride != null && apiBaseUrlOverride!.isNotEmpty;

  bool get hasGoogleMaps => (googleMapsApiKey ?? '').isNotEmpty;

  bool get hasGooglePlaces => (googlePlacesApiKey ?? '').isNotEmpty;

  /// True when a web OAuth client id was supplied at build time.
  bool get hasGoogleSignIn =>
      (googleServerClientId ?? '').trim().isNotEmpty;

  String get apiBaseUrl =>
      apiBaseUrlOverride?.trim().isNotEmpty == true
          ? apiBaseUrlOverride!.trim()
          : name.apiBaseUrl;

  String? get apiKey {
    final value = apiKeyOverride?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  String? get mapsKey {
    final value = googleMapsApiKey?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  String? get placesKey {
    final value = googlePlacesApiKey?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Human-readable summary shown on the Profile screen so it is obvious
  /// which data source the running build is wired to.
  String describe() => switch ((hasBackend, useOfflineData)) {
        (true, false) => 'Connected · ${name.label}',
        (true, true) => 'Offline dataset · ${name.label}',
        (false, _) => 'Offline dataset · no backend configured',
      };

  /// Resolved once at first access. Not a const because the environment name
  /// requires a lookup across the enum.
  static final Environment fromEnvironment = Environment(
    name: _parseEnv(const String.fromEnvironment('LOCALIQ_ENV')),
    apiBaseUrlOverride: const String.fromEnvironment('LOCALIQ_API_BASE_URL'),
    apiKeyOverride: const String.fromEnvironment('LOCALIQ_API_KEY'),
    googleMapsApiKey: const String.fromEnvironment('LOCALIQ_GOOGLE_MAPS_API_KEY'),
    googlePlacesApiKey:
        const String.fromEnvironment('LOCALIQ_GOOGLE_PLACES_API_KEY'),
    googleServerClientId: const String.fromEnvironment(
      'LOCALIQ_GOOGLE_SERVER_CLIENT_ID',
      defaultValue: '582115132932-3gdhql9buvp3oebehq0s8ks4d5i4o8q7.apps.googleusercontent.com',
    ),
    useOfflineData: const bool.fromEnvironment(
      'LOCALIQ_OFFLINE',
      defaultValue: false,
    ),
    requestTimeout: Duration(
      seconds: const int.fromEnvironment(
        'LOCALIQ_TIMEOUT_SECONDS',
        defaultValue: 30,
      ),
    ),
    aiAssistantEnabled: const bool.fromEnvironment(
      'LOCALIQ_AI_ENABLED',
      defaultValue: true,
    ),
  );

  static LocalIqEnvironment _parseEnv(String value) {
    for (final candidate in LocalIqEnvironment.values) {
      if (candidate.name == value) return candidate;
    }
    return LocalIqEnvironment.dev;
  }
}
