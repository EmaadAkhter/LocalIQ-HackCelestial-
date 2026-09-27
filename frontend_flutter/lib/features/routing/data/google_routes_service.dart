import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../../core/network/json_api_client.dart';
import '../../context/domain/context_models.dart';
import '../domain/routes_service.dart';
import 'local_routes_service.dart';

/// Google Routes API (v2:computeRoutes) implementation.
///
/// Requires `LOCALIQ_GOOGLE_MAPS_API_KEY`. When the key is absent or a call
/// fails, gracefully falls back to [LocalRoutesService] so the map and
/// travel-time UI keep working without interruption.
class GoogleRoutesService implements RoutesService {
  GoogleRoutesService({required this.apiKey, this.client, HttpClient? httpClient})
      : _injectedClient = httpClient;

  final String apiKey;
  final JsonApiClient? client;
  final HttpClient? _injectedClient;
  HttpClient? _ownedClient;

  HttpClient get _httpClient =>
      _injectedClient ?? (_ownedClient ??= HttpClient());

  static const _endpoint =
      'https://routes.googleapis.com/directions/v2:computeRoutes';
  static const _fallback = LocalRoutesService();

  @override
  double distanceKm({
    required ({double lat, double lng}) from,
    required ({double lat, double lng}) to,
  }) {
    const earthRadiusKm = 6371.0;
    final dLat = _rad(to.lat - from.lat);
    final dLng = _rad(to.lng - from.lng);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) *
            math.sin(dLng / 2) *
            math.cos(_rad(from.lat)) *
            math.cos(_rad(to.lat));
    return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
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
    if (apiKey.isEmpty) {
      return _fallback.route(from: from, to: to, mode: mode);
    }

    try {
      final googleMode = switch (mode) {
        TravelMode.walk => 'WALK',
        TravelMode.bike => 'BICYCLE',
        TravelMode.transit => 'TRANSIT',
        TravelMode.taxi => 'DRIVE',
      };

      final body = {
        'origin': {
          'location': {
            'latLng': {
              'latitude': from.lat,
              'longitude': from.lng,
            },
          },
        },
        'destination': {
          'location': {
            'latLng': {
              'latitude': to.lat,
              'longitude': to.lng,
            },
          },
        },
        'travelMode': googleMode,
        'routingPreference': mode == TravelMode.walk
            ? 'ROUTING_PREFERENCE_UNSPECIFIED'
            : 'TRAFFIC_AWARE',
      };

      final uri = Uri.parse(_endpoint);
      final req = await _httpClient.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set('X-Goog-Api-Key', apiKey);
      req.headers.set(
        'X-Goog-FieldMask',
        'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.legs',
      );
      req.add(utf8.encode(jsonEncode(body)));
      final resp = await req.close();

      if (resp.statusCode != 200) {
        // Fall back to local routing if Google returns non-200.
        return _fallback.route(from: from, to: to, mode: mode);
      }

      final respBody = await utf8.decoder.bind(resp).join();
      final map = jsonDecode(respBody);
      if (map is! Map) {
        return _fallback.route(from: from, to: to, mode: mode);
      }

      final routes = (map['routes'] as List?) ?? const [];
      if (routes.isEmpty) {
        return _fallback.route(from: from, to: to, mode: mode);
      }

      final routeData = (routes.first as Map).cast<String, dynamic>();
      final legs = ((routeData['legs'] as List?) ?? const [])
          .whereType<Map>()
          .map((l) => l.cast<String, dynamic>())
          .toList();

      final durationSeconds =
          int.tryParse('${routeData['duration']}'.replaceAll('s', '')) ?? 0;
      final distanceMeters =
          int.tryParse('${routeData['distanceMeters']}') ?? 0;

      final polylinePoints = _decodePolyline(
        '${routeData['polyline']?['encodedPolyline'] ?? ''}',
      );

      final totalDistanceKm = distanceMeters > 0
          ? distanceMeters / 1000.0
          : distanceKm(from: from, to: to);
      final totalMinutes = durationSeconds > 0
          ? (durationSeconds / 60).ceil()
          : math.max(2, (totalDistanceKm * 3).round());

      return RoutePlan(
        legs: [
          if (legs.isNotEmpty)
            for (final leg in legs)
              RouteLeg(
                mode: mode,
                minutes: (durationSeconds / 60).ceil(),
                distanceKm: distanceMeters / 1000.0,
                instruction: (leg['steps'] as List?)
                        ?.whereType<Map>()
                        .map((s) =>
                            '${(s['navigationInstruction'] as Map?)?['instructions'] ?? ''}')
                        .where((s) => s.trim().isNotEmpty)
                        .join(' · ') ??
                    'Follow route to destination',
                path: polylinePoints.isNotEmpty
                    ? polylinePoints
                    : _fallbackPolyline(from, to),
              )
          else
            RouteLeg(
              mode: mode,
              minutes: totalMinutes,
              distanceKm: totalDistanceKm,
              instruction: 'Proceed to destination',
              path: polylinePoints.isNotEmpty
                  ? polylinePoints
                  : _fallbackPolyline(from, to),
            ),
        ],
        totalMinutes: totalMinutes,
        totalDistanceKm: totalDistanceKm,
        trafficLevel: TrafficLevel.moderate,
      );
    } catch (_) {
      // Best-effort network route: on any failure, keep working offline.
      return _fallback.route(from: from, to: to, mode: mode);
    }
  }

  static double _rad(double degrees) => degrees * math.pi / 180.0;

  List<({double lat, double lng})> _fallbackPolyline(
    ({double lat, double lng}) from,
    ({double lat, double lng}) to,
  ) =>
      [from, to];

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

  void dispose() {
    _ownedClient?.close(force: true);
  }
}
