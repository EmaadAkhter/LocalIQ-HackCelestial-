import 'dart:convert';

import '../../../core/network/json_api_client.dart';
import '../../context/domain/context_models.dart';
import '../domain/routes_service.dart';

/// Google Routes / Distance Matrix implementation.
///
/// Requires `LOCALIQ_GOOGLE_MAPS_API_KEY`. When the key is absent the
/// provider falls back to [LocalRoutesService] so the map and travel-time UI
/// keep working during development.
class GoogleRoutesService implements RoutesService {
  GoogleRoutesService({required this.apiKey, this.client});

  final String apiKey;
  final JsonApiClient? client;

  Uri get _base => Uri.parse('https://routes.googleapis.com');

  @override
  double distanceKm({
    required ({double lat, double lng}) from,
    required ({double lat, double lng}) to,
  }) {
    // Replace with a Distance Matrix call when the key is present.
    return 0;
  }

  @override
  TravelMode recommendedMode(double distanceKm) {
    if (distanceKm < 1.2) return TravelMode.walk;
    if (distanceKm < 4.5) return TravelMode.transit;
    return TravelMode.taxi;
  }

  @override
  Future<RoutePlan> route({
    required ({double lat, double lng}) from,
    required ({double lat, double lng}) to,
    required TravelMode mode,
  }) async {
    final uri = _base.replace(
      path: '/directions/v2:computeRoutes',
      queryParameters: {
        'key': apiKey,
        'mode': mode == TravelMode.walk ? 'WALK' : 'DRIVE',
        'routingPreference': 'TRAFFIC_AWARE',
        'origin': '${from.lat},${from.lng}',
        'destination': '${to.lat},${to.lng}',
      },
    );
    final api = client;
    if (api == null) {
      throw StateError('GoogleRoutesService needs a JsonApiClient');
    }

    final response = await api.get(uri.toString());
    final map = response is Map ? response.cast<String, dynamic>() : <String, dynamic>{};
    final routes = (map['routes'] as List?) ?? const [];
    if (routes.isEmpty) {
      throw StateError('No route returned by Google Routes');
    }
    final route = (routes.first as Map).cast<String, dynamic>();
    final legs = ((route['legs'] as List?) ?? const [])
        .whereType<Map>()
        .map((l) => l.cast<String, dynamic>())
        .toList();
    final durationSeconds =
        int.tryParse('${route['duration']}'.replaceAll('s', '')) ?? 0;
    final distanceMeters =
        int.tryParse('${route['distanceMeters']}') ?? 0;

    return RoutePlan(
      legs: [
        for (final leg in legs)
          RouteLeg(
            mode: mode,
            minutes: (durationSeconds / 60).ceil(),
            distanceKm: distanceMeters / 1000,
            instruction: (leg['steps'] as List?)
                    ?.whereType<Map>()
                    .map((s) => '${(s['navigationInstruction'] as Map?)?['instructions'] ?? ''}')
                    .join(' · ') ??
                '',
            path: _decodePolyline('${leg['polyline']?['encodedPolyline'] ?? ''}'),
          ),
      ],
      totalMinutes: (durationSeconds / 60).ceil(),
      totalDistanceKm: distanceMeters / 1000,
      trafficLevel: TrafficLevel.moderate,
    );
  }

  /// Standard Google encoded-polyline decoder.
  List<({double lat, double lng})> _decodePolyline(String encoded) {
    if (encoded.isEmpty) return const [];
    final points = <({double lat, double lng})>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      result = 0;
      shift = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add((lat: lat / 1e5, lng: lng / 1e5));
    }
    return points;
  }

  /// Debug helper so the raw payload can be logged without leaking the key.
  String describe(Object response) => const JsonEncoder.withIndent('  ').convert(response);
}
