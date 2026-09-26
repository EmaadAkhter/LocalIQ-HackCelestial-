import '../../context/domain/context_models.dart';
import '../../places/domain/place_repository.dart';

/// Deterministic offline weather source.
///
/// Rather than returning a fixed snapshot, it derives conditions from the
/// supplied clock so a future-dated itinerary still produces sensible
/// opening-hours and weather reasoning during development.
class LocalContextRepository implements ContextRepository {
  LocalContextRepository({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  Future<WeatherSnapshot> weatherAt(GeoPoint point) async {
    final now = _clock();
    // Deterministic pseudo-weather keyed to the day of year.
    final day = DateTime(now.year, now.month, now.day);
    final seed = (day.year * 372 + day.month * 31 + day.day) % 12;
    final monsoonMonth = now.month >= 6 && now.month <= 9;
    final condition = switch (seed) {
      0 || 1 => WeatherCondition.clear,
      2 => WeatherCondition.hot,
      3 => WeatherCondition.cloudy,
      4 || 5 => WeatherCondition.clear,
      _ => monsoonMonth
          ? WeatherCondition.rain
          : (seed.isEven ? WeatherCondition.cloudy : WeatherCondition.clear),
    };
    final base = switch (condition) {
      WeatherCondition.clear => 31,
      WeatherCondition.hot => 36,
      WeatherCondition.cloudy => 29,
      WeatherCondition.rain => 27,
      WeatherCondition.storm => 25,
    };
    return WeatherSnapshot(
      temperatureC: base.toDouble(),
      condition: condition,
      apparentTemperatureC: (base - 1.5).toDouble(),
      humidity: condition == WeatherCondition.rain ? 84 : 62,
      precipitationChance:
          condition == WeatherCondition.rain ? 78 : (condition == WeatherCondition.cloudy ? 30 : 10),
      windKph: 14,
      uvIndex: condition == WeatherCondition.clear ? 9 : 4,
      observedAt: now,
      sunrise: DateTime(now.year, now.month, now.day, 6, 20),
      sunset: DateTime(now.year, now.month, now.day, 18, 45),
    );
  }

  @override
  Future<TrafficSnapshot> trafficAt(GeoPoint point) async {
    final now = _clock();
    final hour = now.hour;
    final weekday = now.weekday <= 5;
    // Two peaks: the morning commute and the evening return.
    final level = switch (hour) {
      >= 8 && < 11 => weekday ? TrafficLevel.heavy : TrafficLevel.moderate,
      >= 11 && < 17 => TrafficLevel.moderate,
      >= 17 && < 21 => weekday ? TrafficLevel.heavy : TrafficLevel.moderate,
      >= 21 && < 24 => TrafficLevel.light,
      _ => TrafficLevel.light,
    };
    return TrafficSnapshot(
      level: level,
      speedMultiplier: level.multiplier,
      updatedAt: now,
    );
  }

  @override
  Future<({WeatherSnapshot weather, TrafficSnapshot traffic})> liveContext(
    GeoPoint point,
  ) async {
    final weather = await weatherAt(point);
    final traffic = await trafficAt(point);
    return (weather: weather, traffic: traffic);
  }
}
