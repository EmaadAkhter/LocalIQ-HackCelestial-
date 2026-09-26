import 'package:flutter/material.dart';

/// App-wide configuration switches.
///
/// No credential is ever stored here as a literal. The Google Maps key is
/// owned by the backend and fetched at startup from `GET /api/v1/config`
/// (see `core/config/runtime_config.dart`), with an optional build-time
/// `--dart-define` as an offline fallback.
abstract final class AppConfig {
  AppConfig._();

  /// Optional offline fallback, injected at build time:
  /// `flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key`.
  /// The backend value always wins when it is reachable.
  static const String buildTimeMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );

  static String _mapsApiKey = buildTimeMapsApiKey;

  /// Effective Google Maps key, from the backend when available.
  static String get mapsApiKey => _mapsApiKey;

  /// Called once by [RuntimeConfig] with the backend-provided key.
  static void applyMapsApiKey(String key) {
    final String trimmed = key.trim();
    if (trimmed.isNotEmpty) _mapsApiKey = trimmed;
  }

  /// Base URL of the FastAPI backend, wired up in a later milestone.
  /// Inject with `--dart-define=API_BASE_URL=http://10.0.2.2:8000`.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// When true the app runs entirely on bundled mock data.
  /// Defaults to **false** so the app talks to the FastAPI backend, which is
  /// the single source of truth for recommendations, Places and Routes.
  /// Run fully offline with: `--dart-define=USE_MOCK_DATA=true`
  static const bool useMockData = bool.fromEnvironment(
    'USE_MOCK_DATA',
    defaultValue: false,
  );

  /// Remote placeholder photography. Disabled in tests for determinism.
  static bool enableRemoteImages = true;

  static bool get hasMapsApiKey => _mapsApiKey.trim().isNotEmpty;
}

abstract final class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;

  /// Horizontal page padding.
  static const double page = 20;
}

abstract final class Radii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}

abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 520);
}
