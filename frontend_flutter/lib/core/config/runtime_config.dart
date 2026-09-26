/// Runtime configuration sourced from the LocalIQ backend.
///
/// The backend is the single source of truth for anything a client needs at
/// runtime (today: the Google Maps key). Clients boot with no key baked in,
/// call `GET /api/v1/config` once during startup, and fall back to the
/// offline experience when the backend is unreachable.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import 'maps_js_loader_stub.dart'
    if (dart.library.html) 'maps_js_loader_web.dart' as maps_js_loader;

/// Fetches public client config and applies it to [AppConfig].
abstract final class RuntimeConfig {
  RuntimeConfig._();

  static const Duration timeout = Duration(seconds: 8);

  static bool _loaded = false;

  /// True once a successful `/api/v1/config` call has been made.
  static bool get isLoaded => _loaded;

  /// Whether the backend reported a usable Google Maps key.
  static bool get mapsEnabled => AppConfig.hasMapsApiKey;

  /// Loads config once per app start. Never throws: a failed call just leaves
  /// the build-time fallback (if any) in place and maps stay offline.
  static Future<void> load({
    String? baseUrl,
    http.Client? client,
  }) async {
    if (_loaded) return;
    final String base = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final http.Client httpClient = client ?? http.Client();
    try {
      final http.Response res = await httpClient
          .get(Uri.parse('$base/api/v1/config'))
          .timeout(timeout);
      if (res.statusCode != 200) return;
      final Map<String, dynamic> data =
          jsonDecode(res.body) as Map<String, dynamic>;
      _loaded = true;
      AppConfig.applyMapsApiKey('${data['google_maps_api_key'] ?? ''}');
      if (data['maps_enabled'] == true) {
        await maps_js_loader.loadMapsJs(AppConfig.mapsApiKey);
      }
    } catch (_) {
      // Offline or backend down: the app keeps working without live maps.
    }
  }
}
