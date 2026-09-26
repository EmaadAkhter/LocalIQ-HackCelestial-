import 'dart:math' as math;

import '../../context/domain/context_models.dart';


import '../../itinerary/domain/itinerary_repository.dart';
import '../../places/domain/place_repository.dart';
import '../../routing/domain/routes_service.dart';

/// Describes the map surface that is actually available. The widgets render a
/// hand-drawn vector map whenever [hasTiles] is false, which keeps the whole
/// map experience working before any key is provisioned.
class GoogleMapService implements MapService {
  const GoogleMapService({required this.hasTiles, this.apiKey});

  @override
  final bool hasTiles;

  @override
  final String? apiKey;

  @override
  String get providerLabel =>
      hasTiles ? 'Google Maps' : 'LocalIQ vector map';

  @override
  Future<MapCameraSpec> cameraFor({
    required List<({double lat, double lng})> points,
    double padding = 0.18,
  }) async {
    if (points.isEmpty) {
      return const MapCameraSpec(
        target: (lat: 18.9322, lng: 72.8316),
        zoom: 12,
        bearing: 0,
      );
    }
    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLng = points.first.lng;
    var maxLng = points.first.lng;
    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLng = math.min(minLng, point.lng);
      maxLng = math.max(maxLng, point.lng);
    }
    final lngSpan = math.max(0.004, (maxLng - minLng) * (1 + padding));
    // Web-mercator: 360° of longitude spans 256·2^zoom pixels, so the zoom
    // that fits `lngSpan` into a 256px viewport is log2(360 / lngSpan).
    final zoom = math.log(360 / (lngSpan * 256)) / math.ln2;
    return MapCameraSpec(
      target: (lat: (minLat + maxLat) / 2, lng: (minLng + maxLng) / 2),
      zoom: zoom.clamp(9, 18),
      bearing: 0,
    );
  }
}

/// Travel-time and hours lookup used by the itinerary repository.
class LocalItineraryGateway implements RecommendationEngineGateway {
  LocalItineraryGateway({required this.routes, required this.places});

  final RoutesService routes;
  final PlaceRepository places;

  @override
  Future<TravelEstimate> travelBetween({
    required ({double lat, double lng}) from,
    required ({double lat, double lng}) to,
  }) async {
    final km = routes.distanceKm(from: from, to: to);
    final mode = routes.recommendedMode(km);
    final plan = await routes.route(from: from, to: to, mode: mode);
    return TravelEstimate(
      minutes: plan.totalMinutes,
      distanceKm: plan.totalDistanceKm,
      mode: mode,
      baselineMinutes: plan.totalMinutes,
      trafficLevel: plan.trafficLevel ?? TrafficLevel.moderate,
    );
  }

  @override
  Future<bool> isOpenAt({
    required String placeId,
    required DateTime at,
  }) async {
    final place = await places.placeById(placeId);
    return place?.openingHours.isOpenAt(at) ?? false;
  }
}
