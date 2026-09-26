import 'dart:math' as math;

import '../../context/domain/context_models.dart';
import '../domain/routes_service.dart';

/// Deterministic offline route + travel-time resolver.
///
/// Mirrors the shape of the Google Routes / Distance Matrix responses so
/// `RemoteRoutesService` can replace it without touching the UI.
class LocalRoutesService implements RoutesService {
  const LocalRoutesService({this.walkKmh = 4.6, this.driveKmh = 24.0});

  final double walkKmh;
  final double driveKmh;

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
    final km = distanceKm(from: from, to: to);
    final speed = switch (mode) {
      TravelMode.walk => walkKmh,
      TravelMode.bike => 14,
      TravelMode.transit => driveKmh * 0.7,
      TravelMode.taxi => driveKmh,
    };
    // Urban routes are never straight lines: apply a circuity factor.
    final effectiveKm = km * 1.32;
    final minutes = math.max(2, ((effectiveKm / speed) * 60).round());

    return RoutePlan(
      legs: [
        RouteLeg(
          mode: mode,
          minutes: minutes,
          distanceKm: km,
          instruction: _instruction(mode, km),
          path: _polyline(from, to),
        ),
      ],
      totalMinutes: minutes,
      totalDistanceKm: km,
      trafficLevel: TrafficLevel.moderate,
    );
  }

  /// Two-point path with a gentle arc, which reads as a real route rather
  /// than a ruler line.
  List<({double lat, double lng})> _polyline(
    ({double lat, double lng}) from,
    ({double lat, double lng}) to,
  ) {
    const steps = 14;
    final midLat = (from.lat + to.lat) / 2;
    final midLng = (from.lng + to.lng) / 2;
    final dLat = to.lat - from.lat;
    final dLng = to.lng - from.lng;
    // Offset perpendicular to the direct line.
    final bulge = 0.12;

    return [
      for (var i = 0; i <= steps; i++)
        (
          lat: midLat + dLat * (i / steps - 0.5) +
              -dLng * math.sin(math.pi * i / steps) * bulge,
          lng: midLng + dLng * (i / steps - 0.5) +
              dLat * math.sin(math.pi * i / steps) * bulge,
        ),
    ];
  }

  static String _instruction(TravelMode mode, double km) {
    return switch (mode) {
      TravelMode.walk => 'Walk ${km.toStringAsFixed(1)} km via the quieter streets',
      TravelMode.bike => 'Cycle ${km.toStringAsFixed(1)} km along the coast road',
      TravelMode.transit => 'Take transit for ${km.toStringAsFixed(1)} km',
      TravelMode.taxi => 'Ride ${km.toStringAsFixed(1)} km by car',
    };
  }

  static double _rad(double degrees) => degrees * math.pi / 180.0;
}
