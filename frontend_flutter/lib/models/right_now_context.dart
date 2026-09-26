import 'package:flutter/material.dart';

/// Live contextual state that drives the Right Now engine.
///
/// All recommendation re-ranking and Right Now badges source from this.
/// The repository/service layer populates this from real APIs;
/// the UI never polls or hardcodes context values directly.
@immutable
class RightNowContext {
  const RightNowContext({
    required this.timestamp,
    this.weatherCondition = WeatherCondition.clear,
    this.temperatureCelsius = 28.0,
    this.rainChancePercent = 0,
    this.crowdLevel = ContextCrowdLevel.moderate,
    this.timeOfDay = TimeOfDayContext.afternoon,
    this.safetyLevel = SafetyLevel.safe,
    this.sunriseAt,
    this.sunsetAt,
    this.localEvents = const [],
    this.closures = const [],
  });

  final DateTime timestamp;
  final WeatherCondition weatherCondition;
  final double temperatureCelsius;
  final int rainChancePercent;
  final ContextCrowdLevel crowdLevel;
  final TimeOfDayContext timeOfDay;
  final SafetyLevel safetyLevel;
  final DateTime? sunriseAt;
  final DateTime? sunsetAt;
  final List<String> localEvents;
  final List<String> closures;

  bool get isRaining => weatherCondition == WeatherCondition.rain ||
      weatherCondition == WeatherCondition.heavyRain;
  bool get isHot => temperatureCelsius > 34;
  bool get isNight => timeOfDay == TimeOfDayContext.night;

  /// Human-readable "Right Now" summary label.
  String get statusLabel {
    if (rainChancePercent > 70) return 'Rain expected soon';
    if (isRaining) return 'Raining now';
    if (crowdLevel == ContextCrowdLevel.low) return 'Low crowd right now';
    if (crowdLevel == ContextCrowdLevel.veryBusy) return 'Very busy now';
    if (isHot) return 'Hot outside — indoors recommended';
    if (timeOfDay == TimeOfDayContext.goldenHour) return 'Golden hour now';
    return 'Good right now';
  }

  String get weatherLabel => switch (weatherCondition) {
        WeatherCondition.clear => '${temperatureCelsius.round()}°C Clear',
        WeatherCondition.cloudy => '${temperatureCelsius.round()}°C Cloudy',
        WeatherCondition.rain => '${temperatureCelsius.round()}°C Rain',
        WeatherCondition.heavyRain => '${temperatureCelsius.round()}°C Heavy rain',
        WeatherCondition.thunderstorm => 'Storm',
        WeatherCondition.fog => '${temperatureCelsius.round()}°C Foggy',
        WeatherCondition.haze => '${temperatureCelsius.round()}°C Hazy',
      };

  static RightNowContext get sample => RightNowContext(
        timestamp: DateTime.now(),
        weatherCondition: WeatherCondition.clear,
        temperatureCelsius: 29.0,
        rainChancePercent: 15,
        crowdLevel: ContextCrowdLevel.moderate,
        timeOfDay: TimeOfDayContext.afternoon,
        safetyLevel: SafetyLevel.safe,
      );
}

enum WeatherCondition { clear, cloudy, rain, heavyRain, thunderstorm, fog, haze }

extension WeatherConditionX on WeatherCondition {
  IconData get icon => switch (this) {
        WeatherCondition.clear => Icons.wb_sunny_outlined,
        WeatherCondition.cloudy => Icons.cloud_outlined,
        WeatherCondition.rain => Icons.umbrella_outlined,
        WeatherCondition.heavyRain => Icons.thunderstorm_outlined,
        WeatherCondition.thunderstorm => Icons.electric_bolt_outlined,
        WeatherCondition.fog => Icons.water_outlined,
        WeatherCondition.haze => Icons.blur_on_outlined,
      };

  Color get color => switch (this) {
        WeatherCondition.clear => const Color(0xFFE0A02A),
        WeatherCondition.cloudy => const Color(0xFF8590A6),
        WeatherCondition.rain => const Color(0xFF2F5BFF),
        WeatherCondition.heavyRain => const Color(0xFF123A6B),
        WeatherCondition.thunderstorm => const Color(0xFF6C55E8),
        WeatherCondition.fog => const Color(0xFF54627A),
        WeatherCondition.haze => const Color(0xFFB07514),
      };
}

enum ContextCrowdLevel { veryLow, low, moderate, busy, veryBusy }

extension ContextCrowdLevelX on ContextCrowdLevel {
  String get label => switch (this) {
        ContextCrowdLevel.veryLow => 'Very quiet',
        ContextCrowdLevel.low => 'Low crowd',
        ContextCrowdLevel.moderate => 'Moderate',
        ContextCrowdLevel.busy => 'Busy',
        ContextCrowdLevel.veryBusy => 'Very busy',
      };
}

enum TimeOfDayContext { earlyMorning, morning, afternoon, goldenHour, evening, night }

enum SafetyLevel { safe, moderate, caution }
