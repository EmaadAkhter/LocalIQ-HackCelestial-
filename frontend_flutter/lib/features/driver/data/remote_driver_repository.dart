import '../../../core/network/json_api_client.dart';
import '../domain/driver_repository.dart';
import '../domain/driver_trip.dart';

/// REST implementation of [DriverRepository].
///
///   GET  /driver/trips
///   GET  /driver/trips/{id}
///   POST /driver/trips/{id}/status    { status }
///   POST /driver/trips/{id}/location  { lat, lng }
class RemoteDriverRepository implements DriverRepository {
  RemoteDriverRepository(this._client);

  final JsonApiClient _client;

  @override
  Future<List<DriverTripSummary>> trips({bool includeCompleted = false}) async {
    final data = await _client.get(
      '/driver/trips',
      query: {'include_completed': includeCompleted},
    );
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => DriverTripSummary.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  @override
  Future<DriverTrip> trip(int id) async {
    final data = await _client.get('/driver/trips/$id');
    return DriverTrip.fromJson((data as Map).cast<String, dynamic>());
  }

  @override
  Future<DriverTrip> setStatus(int id, String status) async {
    final data = await _client.post(
      '/driver/trips/$id/status',
      body: {'status': status},
    );
    return DriverTrip.fromJson((data as Map).cast<String, dynamic>());
  }

  @override
  Future<DriverTrip> reportLocation(
    int id, {
    required double lat,
    required double lng,
  }) async {
    final data = await _client.post(
      '/driver/trips/$id/location',
      body: {'lat': lat, 'lng': lng},
    );
    return DriverTrip.fromJson((data as Map).cast<String, dynamic>());
  }
}
