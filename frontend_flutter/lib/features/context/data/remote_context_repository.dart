import '../../../core/network/json_api_client.dart';
import '../domain/context_models.dart';
import '../../places/domain/place_repository.dart';

/// REST implementation of [ContextRepository].
///
///   GET /weather?lat=&lng=   -> { weather: {...} }
///   GET /traffic?lat=&lng=   -> { traffic: {...} }
///   GET /context/live?lat=&lng= -> { weather: {...}, traffic: {...} }
class RemoteContextRepository implements ContextRepository {
  RemoteContextRepository(this._client);

  final JsonApiClient _client;

  @override
  Future<WeatherSnapshot> weatherAt(GeoPoint point) async {
    final data = await _client.get(
      '/weather',
      query: {'lat': point.latitude, 'lng': point.longitude},
    );
    return WeatherSnapshot.fromJson(_asMap(data, 'weather'));
  }

  @override
  Future<TrafficSnapshot> trafficAt(GeoPoint point) async {
    final data = await _client.get(
      '/traffic',
      query: {'lat': point.latitude, 'lng': point.longitude},
    );
    return TrafficSnapshot.fromJson(_asMap(data, 'traffic'));
  }

  @override
  Future<({WeatherSnapshot weather, TrafficSnapshot traffic})> liveContext(
    GeoPoint point,
  ) async {
    final data = await _client.get(
      '/context/live',
      query: {'lat': point.latitude, 'lng': point.longitude},
    );
    if (data is! Map) throw const FormatException('Unexpected context payload');
    final map = data.cast<String, dynamic>();
    return (
      weather: WeatherSnapshot.fromJson(
        (map['weather'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      traffic: TrafficSnapshot.fromJson(
        (map['traffic'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  static Map<String, dynamic> _asMap(dynamic data, String key) {
    if (data is Map) {
      final map = data.cast<String, dynamic>();
      final nested = map[key];
      if (nested is Map) return nested.cast<String, dynamic>();
      return map;
    }
    throw const FormatException('Expected an object payload');
  }
}
