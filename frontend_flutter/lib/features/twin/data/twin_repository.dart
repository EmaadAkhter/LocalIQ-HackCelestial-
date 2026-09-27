import 'dart:math' as math;

import '../../../core/error/app_exception.dart';
import '../../../core/network/json_api_client.dart';
import '../../context/domain/context_models.dart';
import '../../places/data/local_place_repository.dart';
import '../../places/domain/place_repository.dart';
import '../domain/twin_state.dart';

/// Weather Digital Twin data source.
///
///   GET  /twin/state
///   POST /twin/simulate
abstract class TwinRepository {
  Future<TwinState> state({required GeoPoint centre, double radiusKm});

  Future<TwinState> simulate({
    required GeoPoint centre,
    required RainLevel rainLevel,
    double durationHours,
    double floodMultiplier,
    String? heatLevel,
    double radiusKm,
  });
}

/// Talks to the backend twin (real weather + the real experience graph).
class RemoteTwinRepository implements TwinRepository {
  RemoteTwinRepository(this._client);

  final JsonApiClient _client;

  @override
  Future<TwinState> state({required GeoPoint centre, double radiusKm = 8}) async {
    final data = await _client.get(
      '/twin/state',
      query: {
        'lat': centre.latitude,
        'lng': centre.longitude,
        'radius_km': radiusKm,
      },
    );
    return _parse(data);
  }

  @override
  Future<TwinState> simulate({
    required GeoPoint centre,
    required RainLevel rainLevel,
    double durationHours = 2,
    double floodMultiplier = 1,
    String? heatLevel,
    double radiusKm = 8,
  }) async {
    final data = await _client.post(
      '/twin/simulate',
      body: {
        'rain_level': rainLevel.name,
        'duration_hours': durationHours,
        'flood_multiplier': floodMultiplier,
        'lat': centre.latitude,
        'lng': centre.longitude,
        'radius_km': radiusKm,
        'heat_level': ?heatLevel,
      },
    );
    return _parse(data);
  }

  TwinState _parse(dynamic data) {
    if (data is! Map) {
      throw const ParseException('The weather twin returned an unexpected payload.');
    }
    return TwinState.fromJson(data.cast<String, dynamic>());
  }
}

/// Offline stand-in: runs the same rule-based model over the bundled catalogue,
/// so the what-if demo still works with no connection.
class LocalTwinRepository implements TwinRepository {
  LocalTwinRepository({PlaceRepository? places})
      : _places = places ?? LocalPlaceRepository();

  final PlaceRepository _places;

  static const _floodPropensity = 0.5;

  @override
  Future<TwinState> state({required GeoPoint centre, double radiusKm = 8}) =>
      simulate(centre: centre, rainLevel: RainLevel.light, radiusKm: radiusKm);

  @override
  Future<TwinState> simulate({
    required GeoPoint centre,
    required RainLevel rainLevel,
    double durationHours = 2,
    double floodMultiplier = 1,
    String? heatLevel,
    double radiusKm = 8,
  }) async {
    final rain = rainLevel.intensity;
    final places = await _places.search(const PlaceQuery(limit: 0));

    final nearby = places
        .where((p) => _haversineKm(centre, p.centre) <= radiusKm)
        .toList();
    final inPlay = nearby.isEmpty ? places : nearby;

    final durationFactor = (0.5 + durationHours / 6).clamp(0.5, 1.0);
    final flood =
        (_floodPropensity * rain * durationFactor * floodMultiplier).clamp(0.0, 1.0);
    final floodLevel = flood >= 0.6 ? 'HIGH' : flood >= 0.3 ? 'MEDIUM' : 'LOW';
    final movement = 1 + rain * 0.3 + flood * 0.35;

    final experiences = <TwinExperience>[];
    for (final p in inPlay) {
      final io = p.indoor ? 1.0 : 0.0;
      var score = 78.0 - rain * 65.0 * (1 - io) + rain * 18.0 * io - flood * 25.0;
      score = score.clamp(0.0, 100.0);
      experiences.add(
        TwinExperience(
          id: int.tryParse(p.id) ?? p.id.hashCode,
          name: p.name,
          category: p.category.name,
          lat: p.centre.latitude,
          lng: p.centre.longitude,
          indoorOutdoor: p.indoor ? 'indoor' : 'outdoor',
          suitability: score,
          riskFlags: [
            if (rain >= 0.6) (io >= 0.5 ? 'rain-safe indoor' : 'heavy rain exposure')
            else if (rain >= 0.3) 'light rain',
            if (flood >= 0.6) 'flood risk nearby',
            if (rain < 0.3 && flood < 0.6) 'good conditions',
          ],
          demandMultiplier: 1 + rain * 1.3 * io,
          indoorRatio: io,
          infeasible: score < 40,
        ),
      );
    }

    final areaName = inPlay.isNotEmpty ? inPlay.first.area : 'Mumbai';
    final areas = [
      TwinArea(
        name: areaName,
        floodRiskLevel: floodLevel,
        floodRiskScore: flood,
        movementSlowdownFactor: movement,
        heatStressLevel: 'LOW',
        indoorDemandBoost: 0,
        mentions: 0,
      ),
    ];

    final outdoor = experiences.where((e) => e.indoorRatio < 0.5).toList();
    final impacted = outdoor.where((e) => e.infeasible).toList();
    final indoor = experiences.where((e) => e.indoorRatio >= 0.5).toList();
    final peak = indoor.fold<double>(
      1,
      (m, e) => e.demandMultiplier > m ? e.demandMultiplier : m,
    );
    final rankedIndoor = [...indoor]
      ..sort((a, b) => b.suitability.compareTo(a.suitability));
    final rankedOutdoor = [...outdoor]
      ..sort((a, b) => b.suitability.compareTo(a.suitability));

    final pct = outdoor.isEmpty ? 0.0 : 100.0 * impacted.length / outdoor.length;
    return TwinState(
      rainLevel: rainLevel,
      rainIntensity: rain,
      durationHours: durationHours,
      floodMultiplier: floodMultiplier,
      heatLevel: heatLevel ?? 'normal',
      areas: areas,
      experiences: experiences,
      summary: TwinSummary(
        outdoorImpactedPct: pct,
        peakIndoorDemand: peak,
        highFloodAreas: floodLevel == 'HIGH' ? [areaName] : const [],
        avgMovementSlowdown: movement,
        narrative: [
          impacted.isEmpty
              ? 'Outdoor experiences stay feasible.'
              : '${pct.round()}% of outdoor experiences become infeasible.',
          'Indoor demand peaks at ${peak.toStringAsFixed(1)}x.',
          'Average movement speed reduced by ${((movement - 1) * 100).round()}%.',
        ],
        suggestedSwitch: impacted.isNotEmpty && rankedIndoor.isNotEmpty
            ? TwinSwitch(
                from: rankedOutdoor.isNotEmpty
                    ? rankedOutdoor.first.name
                    : impacted.first.name,
                to: rankedIndoor.first.name,
              )
            : null,
      ),
    );
  }

  static double _haversineKm(GeoPoint a, GeoPoint b) {
    const earthKm = 6371.0;
    double rad(double deg) => deg * math.pi / 180.0;
    final dLat = rad(b.latitude - a.latitude);
    final dLng = rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(a.latitude)) *
            math.cos(rad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * earthKm * math.asin(math.sqrt(h));
  }
}
