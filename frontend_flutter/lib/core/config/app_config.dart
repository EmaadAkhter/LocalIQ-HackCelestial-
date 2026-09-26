import 'package:flutter/widgets.dart';

import 'environment.dart';

/// Typed application settings derived from [Environment] plus runtime
/// preferences. Injected through Riverpod so tests can override cleanly.
@immutable
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.hasBackend,
    required this.offlineMode,
    required this.requestTimeout,
    required this.mapsEnabled,
    required this.placesEnabled,
    required this.assistantEnabled,
    required this.sourceLabel,
  });

  final LocalIqEnvironment environment;
  final String apiBaseUrl;
  final bool hasBackend;
  final bool offlineMode;
  final Duration requestTimeout;
  final bool mapsEnabled;
  final bool placesEnabled;
  final bool assistantEnabled;
  final String sourceLabel;

  factory AppConfig.fromEnvironment(Environment env) {
    return AppConfig(
      environment: env.name,
      apiBaseUrl: env.apiBaseUrl,
      hasBackend: env.hasBackend,
      offlineMode: env.useOfflineData || !env.hasBackend,
      requestTimeout: env.requestTimeout,
      mapsEnabled: env.hasGoogleMaps,
      placesEnabled: env.hasGooglePlaces,
      assistantEnabled: env.aiAssistantEnabled,
      sourceLabel: env.describe(),
    );
  }
}
