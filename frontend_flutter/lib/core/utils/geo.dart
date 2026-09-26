import 'dart:math' as math;

/// Offline geo helpers — mirrors the FastAPI heuristic so the UI shows the
/// same numbers the backend will return once connected.
abstract final class Geo {
  Geo._();

  static const double earthRadiusKm = 6371.0;
  static const double averageCitySpeedKmh = 20.0;
  static const int minimumTravelMinutes = 10;
  static const int overheadMinutes = 8;

  static double haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadiusKm * math.asin(math.sqrt(a));
  }

  static int travelMinutes(double distanceKm) {
    if (distanceKm <= 0) return minimumTravelMinutes;
    final minutes = (distanceKm / averageCitySpeedKmh) * 60 + overheadMinutes;
    return math.max(minimumTravelMinutes, minutes.round());
  }

  static double _rad(double degrees) => degrees * math.pi / 180.0;
}
