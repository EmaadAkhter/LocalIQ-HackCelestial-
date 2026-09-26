import 'package:flutter/foundation.dart';

import '../../context/domain/context_models.dart';
import '../../../core/utils/json_map_x.dart';

/// How a traveller gets from A to B.
enum TravelMode { walk, transit, taxi, bike }

extension TravelModeX on TravelMode {
  String get label => switch (this) {
        TravelMode.walk => 'Walk',
        TravelMode.transit => 'Transit',
        TravelMode.taxi => 'Taxi',
        TravelMode.bike => 'Bike',
      };

  static TravelMode parse(String? value) {
    if (value == null) return TravelMode.walk;
    final needle = value.toLowerCase();
    return TravelMode.values.firstWhere(
      (m) => m.name.toLowerCase() == needle || m.label.toLowerCase() == needle,
      orElse: () => TravelMode.walk,
    );
  }
}

/// A travel leg to or from a place, resolved for a specific context.
@immutable
class TravelEstimate {
  const TravelEstimate({
    required this.minutes,
    required this.distanceKm,
    required this.mode,
    required this.baselineMinutes,
    required this.trafficLevel,
  });

  final int minutes;
  final double distanceKm;
  final TravelMode mode;

  /// Free-flow estimate before traffic is applied.
  final int baselineMinutes;
  final TrafficLevel trafficLevel;

  String get label => '$minutes min · ${distanceKm.toStringAsFixed(1)} km';

  factory TravelEstimate.fromJson(Map<String, dynamic> json) {
    return TravelEstimate(
      minutes: json.intValue('minutes', fallback: 10),
      distanceKm: json.doubleValue('distanceKm', fallback: 1.2),
      mode: TravelModeX.parse(json.string('mode')),
      baselineMinutes: json.intValue('baselineMinutes', fallback: 10),
      trafficLevel: TrafficLevel.parse(json.string('trafficLevel')),
    );
  }

  Map<String, dynamic> toJson() => {
        'minutes': minutes,
        'distance_km': distanceKm,
        'mode': mode.name,
        'baseline_minutes': baselineMinutes,
        'traffic_level': trafficLevel.name,
      };
}

/// A resolved route between two points, with the legs the UI renders.
class RouteLeg {
  const RouteLeg({
    required this.mode,
    required this.minutes,
    required this.distanceKm,
    required this.instruction,
    required this.path,
  });

  final TravelMode mode;
  final int minutes;
  final double distanceKm;
  final String instruction;

  /// Encoded polyline or coordinate list for the map layer.
  final List<({double lat, double lng})> path;
}

class RoutePlan {
  const RoutePlan({
    required this.legs,
    required this.totalMinutes,
    required this.totalDistanceKm,
    required this.trafficLevel,
  });

  final List<RouteLeg> legs;
  final int totalMinutes;
  final double totalDistanceKm;
  final TrafficLevel? trafficLevel;

  String get label =>
      '${totalMinutes.toStringAsFixed(0)} min · ${totalDistanceKm.toStringAsFixed(1)} km';
}

/// Travel-time and route resolution. Backed by Google Routes/Distance Matrix
/// in production, a deterministic local estimator offline.
abstract interface class RoutesService {
  Future<RoutePlan> route({
    required ({double lat, double lng}) from,
    required ({double lat, double lng}) to,
    required TravelMode mode,
  });

  /// Straight-line distance in km.
  double distanceKm({
    required ({double lat, double lng}) from,
    required ({double lat, double lng}) to,
  });

  /// Cheapest workable mode for a distance band.
  TravelMode recommendedMode(double distanceKm);
}

/// The map surface. Decouples rendering from the provider so the app can run
/// with a hand-drawn vector map and switch to Google Maps by configuration.
///
/// A `MapController` implementation backed by `google_maps_flutter` would slot
/// in here; the widgets above only consume [MapMarker] / [MapPolyline].
abstract interface class MapService {
  /// Whether a real tile provider is configured. Drives which surface renders.
  bool get hasTiles;

  /// Google Maps needs an API key; without one we fall back to the vector map.
  String? get apiKey;

  String get providerLabel;

  Future<MapCameraSpec> cameraFor({
    required List<({double lat, double lng})> points,
    double padding = 0.18,
  });
}

class MapCameraSpec {
  const MapCameraSpec({
    required this.target,
    required this.zoom,
    required this.bearing,
  });

  final ({double lat, double lng}) target;
  final double zoom;
  final double bearing;
}

/// A pin rendered by whichever map surface is active.
class MapMarker {
  const MapMarker({
    required this.id,
    required this.position,
    required this.label,
    this.rank,
    this.tone,
    this.onTap,
  });

  final String id;
  final ({double lat, double lng}) position;
  final String label;
  final int? rank;

  /// Semantic tone (feasible / partial / blocked) mapped to a colour.
  final String? tone;
  final VoidCallback? onTap;
}

class MapPolyline {
  const MapPolyline({required this.points, this.tone = 'route'});

  final List<({double lat, double lng})> points;
  final String tone;
}
