import 'package:flutter/foundation.dart';

import '../../../core/utils/json_map_x.dart';

/// Rain intensity knob for the Digital Twin what-if simulator.
enum RainLevel {
  none('None', 0.0),
  light('Light', 0.35),
  heavy('Heavy', 0.7),
  storm('Storm', 1.0);

  const RainLevel(this.label, this.intensity);

  final String label;
  final double intensity;

  static RainLevel parse(String? value) {
    final needle = (value ?? '').toLowerCase();
    return RainLevel.values.firstWhere(
      (r) => r.name == needle,
      orElse: () => RainLevel.heavy,
    );
  }
}

/// One experience as the twin sees it under the current scenario.
@immutable
class TwinExperience {
  const TwinExperience({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.indoorOutdoor,
    required this.suitability,
    required this.riskFlags,
    required this.demandMultiplier,
    required this.indoorRatio,
    required this.infeasible,
  });

  final int id;
  final String name;
  final String category;
  final double lat;
  final double lng;
  final String indoorOutdoor;
  final double suitability;
  final List<String> riskFlags;
  final double demandMultiplier;
  final double indoorRatio;
  final bool infeasible;

  /// Green / amber / red band used by the map + lists.
  String get impactTone {
    if (suitability >= 70) return 'feasible';
    if (suitability >= 40) return 'partial';
    return 'blocked';
  }

  factory TwinExperience.fromJson(Map<String, dynamic> json) {
    return TwinExperience(
      id: json.intValue('id'),
      name: json.string('name') ?? 'Place',
      category: json.string('category') ?? '',
      lat: json.doubleValue('lat'),
      lng: json.doubleValue('lng'),
      indoorOutdoor: json.string('indoorOutdoor') ?? 'indoor',
      suitability: json.doubleValue('weatherSuitabilityScore'),
      riskFlags: json.stringList('riskFlags'),
      demandMultiplier: json.doubleValue('demandMultiplier', fallback: 1),
      indoorRatio: json.doubleValue('indoorRatio', fallback: 1),
      infeasible: json.boolValue('infeasible'),
    );
  }
}

/// Weather-driven state for one area.
@immutable
class TwinArea {
  const TwinArea({
    required this.name,
    required this.floodRiskLevel,
    required this.floodRiskScore,
    required this.movementSlowdownFactor,
    required this.heatStressLevel,
    required this.indoorDemandBoost,
    required this.mentions,
  });

  final String name;
  final String floodRiskLevel;
  final double floodRiskScore;
  final double movementSlowdownFactor;
  final String heatStressLevel;
  final double indoorDemandBoost;
  final int mentions;

  bool get isFlooding => floodRiskLevel == 'HIGH';

  factory TwinArea.fromJson(Map<String, dynamic> json) {
    return TwinArea(
      name: json.string('name') ?? 'Area',
      floodRiskLevel: json.string('floodRiskLevel') ?? 'LOW',
      floodRiskScore: json.doubleValue('floodRiskScore'),
      movementSlowdownFactor: json.doubleValue('movementSlowdownFactor', fallback: 1),
      heatStressLevel: json.string('heatStressLevel') ?? 'LOW',
      indoorDemandBoost: json.doubleValue('indoorDemandBoost'),
      mentions: json.intValue('mentions'),
    );
  }
}

/// A concrete before/after suggestion the demo can show.
@immutable
class TwinSwitch {
  const TwinSwitch({required this.from, required this.to});

  final String from;
  final String to;

  factory TwinSwitch.fromJson(Map<String, dynamic> json) => TwinSwitch(
        from: json.string('from') ?? '',
        to: json.string('to') ?? '',
      );
}

/// Cascading effects of the scenario.
@immutable
class TwinSummary {
  const TwinSummary({
    required this.outdoorImpactedPct,
    required this.peakIndoorDemand,
    required this.highFloodAreas,
    required this.avgMovementSlowdown,
    required this.narrative,
    this.suggestedSwitch,
  });

  final double outdoorImpactedPct;
  final double peakIndoorDemand;
  final List<String> highFloodAreas;
  final double avgMovementSlowdown;
  final List<String> narrative;
  final TwinSwitch? suggestedSwitch;

  factory TwinSummary.fromJson(Map<String, dynamic> json) {
    final rawSwitch = json.mapOrEmpty('suggestedSwitch');
    return TwinSummary(
      outdoorImpactedPct: json.doubleValue('outdoorImpactedPct'),
      peakIndoorDemand: json.doubleValue('peakIndoorDemandMultiplier', fallback: 1),
      highFloodAreas: json.stringList('highFloodAreas'),
      avgMovementSlowdown: json.doubleValue('avgMovementSlowdown', fallback: 1),
      narrative: json.stringList('narrative'),
      suggestedSwitch:
          rawSwitch.isEmpty ? null : TwinSwitch.fromJson(rawSwitch),
    );
  }
}

/// Full twin snapshot for a scenario.
@immutable
class TwinState {
  const TwinState({
    required this.rainLevel,
    required this.rainIntensity,
    required this.durationHours,
    required this.floodMultiplier,
    required this.heatLevel,
    required this.areas,
    required this.experiences,
    required this.summary,
  });

  final RainLevel rainLevel;
  final double rainIntensity;
  final double durationHours;
  final double floodMultiplier;
  final String heatLevel;
  final List<TwinArea> areas;
  final List<TwinExperience> experiences;
  final TwinSummary summary;

  factory TwinState.fromJson(Map<String, dynamic> json) {
    final scenario = json.mapOrEmpty('scenario');
    return TwinState(
      rainLevel: RainLevel.parse(scenario.string('rainLevel')),
      rainIntensity: scenario.doubleValue('rainIntensity'),
      durationHours: scenario.doubleValue('durationHours', fallback: 2),
      floodMultiplier: scenario.doubleValue('floodMultiplier', fallback: 1),
      heatLevel: scenario.string('heatLevel') ?? 'normal',
      areas: json.mapOrEmptyList('areas').map(TwinArea.fromJson).toList(),
      experiences:
          json.mapOrEmptyList('experiences').map(TwinExperience.fromJson).toList(),
      summary: TwinSummary.fromJson(json.mapOrEmpty('summary')),
    );
  }
}
