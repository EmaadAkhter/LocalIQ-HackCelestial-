import 'package:flutter/foundation.dart';

import '../../../core/utils/json_map_x.dart';

/// A geographic point. Shared by places, routes and the user context.
@immutable
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        latitude: json.doubleValue('latitude', fallback: 0),
        longitude: json.doubleValue('longitude', fallback: 0),
      );

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Broad category taxonomy used for interest matching and browse filters.
enum ExperienceCategory {
  food('Food', 'Tasting, cafés, markets'),
  culture('Culture', 'Museums, institutions, heritage'),
  history('History', 'Colonial, civic, archival'),
  art('Art', 'Galleries, studios, public art'),
  nature('Nature', 'Waterfront, parks, viewpoints'),
  heritage('Heritage', 'Landmarks, monuments, architecture'),
  nightlife('Nightlife', 'Bars, live music, late hours'),
  shopping('Shopping', 'Bazaars, craft, independent retail'),
  wellness('Wellness', 'Movement, quiet, restoration'),
  adventure('Adventure', 'Active, high-energy, outdoors'),
  localLife('Local Life', 'Neighbourhood texture and routines');

  const ExperienceCategory(this.label, this.blurb);

  final String label;
  final String blurb;

  static ExperienceCategory parse(String? value) {
    if (value == null) return ExperienceCategory.localLife;
    final needle = value.toLowerCase();
    return ExperienceCategory.values.firstWhere(
      (c) => c.name.toLowerCase() == needle || c.label.toLowerCase() == needle,
      orElse: () => ExperienceCategory.localLife,
    );
  }
}

/// Who is travelling. Drives ranking, venue fit and copy.
enum GroupType {
  solo('Solo', 'One person, full control of the pace'),
  couple('Couple', 'Quieter, more atmospheric options'),
  friends('Friends', 'Social, flexible, food-forward'),
  family('Family', 'Short, low-walking, all-ages options'),
  team('Team', 'Efficient, scheduled, group-friendly');

  const GroupType(this.label, this.blurb);

  final String label;
  final String blurb;

  static GroupType parse(String? value) {
    if (value == null) return GroupType.solo;
    final needle = value.toLowerCase();
    return GroupType.values.firstWhere(
      (g) => g.name.toLowerCase() == needle || g.label.toLowerCase() == needle,
      orElse: () => GroupType.solo,
    );
  }
}

/// Mobility and access needs. Treated as a hard filter when strict.
enum AccessibilityNeed {
  none('No preference', 'Any route is fine'),
  lowWalking('Low walking', 'Keep walking legs under ~15 minutes'),
  stepFree('Step-free', 'Avoid stairs and uneven ground'),
  indoorPreferred('Indoor preferred', 'Prioritise covered, air-conditioned'),
  wheelchair('Wheelchair accessible', 'Step-free with accessible facilities');

  const AccessibilityNeed(this.label, this.blurb);

  final String label;
  final String blurb;

  bool get isStrict => this == AccessibilityNeed.stepFree || this == AccessibilityNeed.wheelchair;

  static AccessibilityNeed parse(String? value) {
    if (value == null) return AccessibilityNeed.none;
    final needle = value.toLowerCase();
    return AccessibilityNeed.values.firstWhere(
      (a) =>
          a.name.toLowerCase() == needle ||
          a.label.toLowerCase() == needle ||
          a.label.toLowerCase() == 'low walking' && needle.contains('low walking'),
      orElse: () => AccessibilityNeed.none,
    );
  }
}

/// Live conditions for the discovery area.
@immutable
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureC,
    required this.condition,
    required this.apparentTemperatureC,
    required this.humidity,
    required this.precipitationChance,
    required this.windKph,
    required this.uvIndex,
    required this.observedAt,
    required this.sunrise,
    required this.sunset,
  });

  final double temperatureC;
  final WeatherCondition condition;
  final double apparentTemperatureC;
  final int humidity;
  final int precipitationChance;
  final double windKph;
  final double uvIndex;
  final DateTime observedAt;
  final DateTime sunrise;
  final DateTime sunset;

  String get temperatureLabel => '${temperatureC.round()}°';

  String get summary => '$temperatureLabel · ${condition.label}';

  bool get isWet => condition == WeatherCondition.rain ||
      condition == WeatherCondition.storm ||
      precipitationChance >= 55;

  /// Human-readable guidance that the ranking engine surfaces verbatim.
  String get planningNote => switch (condition) {
        WeatherCondition.rain ||
        WeatherCondition.storm =>
          'Outdoor stops are deprioritised — covered and indoor picks rank first.',
        WeatherCondition.clear =>
          'Outdoor and waterfront options rank higher. Carry water and plan for sun.',
        WeatherCondition.cloudy =>
          'Mixed indoor and outdoor ranking. Comfortable walking conditions.',
        WeatherCondition.hot =>
          'Midday heat — shaded or indoor stops rank higher. Hydration breaks help.',
      };

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) {
    return WeatherSnapshot(
      temperatureC: json.doubleValue('temperatureC', fallback: 28),
      condition: WeatherCondition.parse(json.string('condition')),
      apparentTemperatureC:
          json.doubleValue('apparentTemperatureC', fallback: 28),
      humidity: json.intValue('humidity', fallback: 70),
      precipitationChance: json.intValue('precipitationChance', fallback: 20),
      windKph: json.doubleValue('windKph', fallback: 12),
      uvIndex: json.doubleValue('uvIndex', fallback: 5),
      observedAt:
          DateTime.tryParse(json.stringOrNull('observedAt') ?? '') ?? DateTime.now(),
      sunrise:
          DateTime.tryParse(json.stringOrNull('sunrise') ?? '') ?? DateTime.now(),
      sunset:
          DateTime.tryParse(json.stringOrNull('sunset') ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'temperature_c': temperatureC,
        'condition': condition.name,
        'apparent_temperature_c': apparentTemperatureC,
        'humidity': humidity,
        'precipitation_chance': precipitationChance,
        'wind_kph': windKph,
        'uv_index': uvIndex,
        'observed_at': observedAt.toIso8601String(),
        'sunrise': sunrise.toIso8601String(),
        'sunset': sunset.toIso8601String(),
      };
}

enum WeatherCondition {
  clear('Clear', 'sun'),
  cloudy('Cloudy', 'cloud'),
  rain('Rain', 'rain'),
  storm('Storm', 'storm'),
  hot('Hot', 'hot');

  const WeatherCondition(this.label, this.iconKey);

  final String label;
  final String iconKey;

  static WeatherCondition parse(String? value) {
    if (value == null) return WeatherCondition.cloudy;
    final needle = value.toLowerCase();
    return WeatherCondition.values.firstWhere(
      (c) => c.name.toLowerCase() == needle || c.label.toLowerCase() == needle,
      orElse: () => WeatherCondition.cloudy,
    );
  }
}

/// Road/transit conditions that affect travel-time estimates.
@immutable
class TrafficSnapshot {
  const TrafficSnapshot({
    required this.level,
    required this.speedMultiplier,
    required this.updatedAt,
  });

  final TrafficLevel level;

  /// Multiplier applied to baseline travel times (>1 means slower).
  final double speedMultiplier;
  final DateTime updatedAt;

  String get label => level.label;

  /// Scales a free-flow travel estimate into a current estimate.
  int adjust(int baselineMinutes) {
    if (baselineMinutes <= 0) return 0;
    return (baselineMinutes * speedMultiplier).round().clamp(3, 240);
  }

  factory TrafficSnapshot.fromJson(Map<String, dynamic> json) {
    return TrafficSnapshot(
      level: TrafficLevel.parse(json.string('level')),
      speedMultiplier: json.doubleValue('speedMultiplier', fallback: 1.0),
      updatedAt:
          DateTime.tryParse(json.stringOrNull('updatedAt') ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'level': level.name,
        'speed_multiplier': speedMultiplier,
        'updated_at': updatedAt.toIso8601String(),
      };
}

enum TrafficLevel {
  light('Light traffic', 0.9),
  moderate('Moderate traffic', 1.15),
  heavy('Heavy traffic', 1.45),
  severe('Severe congestion', 1.8);

  const TrafficLevel(this.label, this.multiplier);

  final String label;
  final double multiplier;

  static TrafficLevel parse(String? value) {
    if (value == null) return TrafficLevel.moderate;
    final needle = value.toLowerCase();
    return TrafficLevel.values.firstWhere(
      (t) => t.name.toLowerCase() == needle || t.label.toLowerCase() == needle,
      orElse: () => TrafficLevel.moderate,
    );
  }
}

/// Opening-hours model supporting split days (e.g. closed Tuesday).
@immutable
class OpeningHours {
  const OpeningHours({required this.weekly, this.specialNote});

  /// Day-of-week (1 = Monday) to `[openMinutes, closeMinutes]`. Minutes from
  /// midnight; an empty list means closed that day.
  final Map<int, List<IntRange>> weekly;
  final String? specialNote;

  static const empty = OpeningHours(weekly: {});

  bool isOpenAt(DateTime time) {
    final ranges = weekly[time.weekday];
    if (ranges == null || ranges.isEmpty) return false;
    final minutes = time.hour * 60 + time.minute;
    return ranges.any((r) => minutes >= r.start && minutes <= r.end);
  }

  int? closeMinutesFor(DateTime time) {
    final ranges = weekly[time.weekday];
    if (ranges == null || ranges.isEmpty) return null;
    for (final range in ranges.reversed) {
      final minutes = time.hour * 60 + time.minute;
      if (minutes >= range.start && minutes <= range.end) return range.end;
    }
    return null;
  }

  String describeFor(DateTime time) {
    final ranges = weekly[time.weekday];
    if (ranges == null || ranges.isEmpty) {
      return 'Closed on ${_dayName(time.weekday)}';
    }
    final windows = ranges
        .map((r) => '${_clock(r.start)} – ${_clock(r.end)}')
        .join(', ');
    if (!isOpenAt(time)) {
      final first = ranges.first;
      return 'Closed now · opens ${_clock(first.start)}';
    }
    return 'Open now · $windows';
  }

  static String _clock(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final display = h % 12 == 0 ? 12 : h % 12;
    return '$display:${m.toString().padLeft(2, '0')} $suffix';
  }

  static String _dayName(int weekday) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][(weekday - 1).clamp(0, 6)];

  /// Parses either a structured map or a compact `"10:00-18:00"` string.
  factory OpeningHours.fromJson(Map<String, dynamic> json) {
    final raw = json.pick('weekly');
    final weekly = <int, List<IntRange>>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final day = int.tryParse(entry.key.toString());
        if (day == null) continue;
        final value = entry.value;
        if (value is List) {
          weekly[day] = value
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .map(
                (e) => IntRange(
                  e.intValue('start'),
                  e.intValue('end'),
                ),
              )
              .toList();
        } else if (value is String) {
          final parsed = _parseCompact(value);
          if (parsed.isNotEmpty) weekly[day] = parsed;
        }
      }
    }
    return OpeningHours(
      weekly: weekly,
      specialNote: json.stringOrNull('specialNote'),
    );
  }

  static List<IntRange> _parseCompact(String value) {
    return value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.contains('-'))
        .map((part) {
          final halves = part.split('-');
          return IntRange(_toMinutes(halves.first), _toMinutes(halves.last));
        })
        .toList();
  }

  static int _toMinutes(String value) {
    final bits = value.trim().split(':');
    final h = int.tryParse(bits.first) ?? 0;
    final m = bits.length > 1 ? (int.tryParse(bits[1]) ?? 0) : 0;
    return h * 60 + m;
  }

  Map<String, dynamic> toJson() => {
        'weekly': {
          for (final entry in weekly.entries)
            entry.key.toString(): [
              for (final range in entry.value)
                {'start': range.start, 'end': range.end},
            ],
        },
        if (specialNote != null) 'special_note': specialNote,
      };
}

@immutable
class IntRange {
  const IntRange(this.start, this.end);

  final int start;
  final int end;
}

/// Access characteristics of a place, used for accessibility filtering.
@immutable
class AccessibilityProfile {
  const AccessibilityProfile({
    this.stepFree = true,
    this.wheelchairAccessible = true,
    this.restrooms = true,
    this.seatingAvailable = true,
    this.maxWalkingMinutes = 15,
    this.notes,
  });

  final bool stepFree;
  final bool wheelchairAccessible;
  final bool restrooms;
  final bool seatingAvailable;
  final int maxWalkingMinutes;
  final String? notes;

  static const standard = AccessibilityProfile();

  factory AccessibilityProfile.fromJson(Map<String, dynamic> json) {
    return AccessibilityProfile(
      stepFree: json.boolValue('stepFree', fallback: true),
      wheelchairAccessible: json.boolValue('wheelchairAccessible', fallback: true),
      restrooms: json.boolValue('restrooms', fallback: true),
      seatingAvailable: json.boolValue('seatingAvailable', fallback: true),
      maxWalkingMinutes: json.intValue('maxWalkingMinutes', fallback: 15),
      notes: json.stringOrNull('notes'),
    );
  }

  Map<String, dynamic> toJson() => {
        'step_free': stepFree,
        'wheelchair_accessible': wheelchairAccessible,
        'restrooms': restrooms,
        'seating_available': seatingAvailable,
        'max_walking_minutes': maxWalkingMinutes,
        if (notes != null) 'notes': notes,
      };
}
