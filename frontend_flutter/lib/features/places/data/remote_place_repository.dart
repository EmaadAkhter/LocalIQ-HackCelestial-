import '../../../core/error/app_exception.dart';
import '../../../core/network/json_api_client.dart';
import '../../context/domain/context_models.dart';
import '../../context/domain/discovery_context.dart';
import '../domain/place_repository.dart';
import '../domain/place.dart';

/// REST implementation of [PlaceRepository].
///
/// Endpoints expected from the backend (FastAPI):
///   GET /places?text=&lat=&lng=&radius_km=&categories=&limit=
///   GET /places/{id}
///   GET /places/{id}/experiences
///   GET /places/popular?lat=&lng=&radius_km=&limit=
///   GET /places/gems?lat=&lng=&radius_km=&limit=
///   GET /places/discover?text=...
class RemotePlaceRepository implements PlaceRepository {
  RemotePlaceRepository(this._client);

  final JsonApiClient _client;

  @override
  Future<List<Place>> search(PlaceQuery query) async {
    final data = await _client.get(
      '/places',
      query: _toQuery(query),
    );
    if (data is! List) throw const ParseException('Unexpected /places payload.');
    return data
        .whereType<Map>()
        .map((e) => Place.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<Place?> placeById(String id) async {
    try {
      final data = await _client.get('/places/$id');
      if (data is Map) return Place.fromJson(data.cast<String, dynamic>());
      return null;
    } on NotFoundException {
      return null;
    }
  }

  @override
  Future<List<Experience>> experiencesForPlace(String placeId) async {
    final data = await _client.get('/places/$placeId/experiences');
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => Experience.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<Experience?> experienceById(String id) async {
    try {
      final data = await _client.get('/experiences/$id');
      if (data is Map) return Experience.fromJson(data.cast<String, dynamic>());
      return null;
    } on NotFoundException {
      return null;
    }
  }

  @override
  Future<List<Place>> popularNearby({
    required GeoPoint near,
    double radiusKm = 6,
    int limit = 12,
  }) async {
    final data = await _client.get(
      '/places/popular',
      query: {
        'lat': near.latitude,
        'lng': near.longitude,
        'radius_km': radiusKm,
        'limit': limit,
      },
    );
    return _decodeList(data);
  }

  @override
  Future<List<Place>> localGems({
    required GeoPoint near,
    double radiusKm = 8,
    int limit = 12,
  }) async {
    final data = await _client.get(
      '/places/gems',
      query: {
        'lat': near.latitude,
        'lng': near.longitude,
        'radius_km': radiusKm,
        'limit': limit,
      },
    );
    return _decodeList(data);
  }

  @override
  Future<PlaceQueryResult> discover(PlaceQuery query) async {
    final data = await _client.get(
      '/places/discover',
      query: _toQuery(query),
    );
    if (data is! Map) throw const ParseException('Unexpected /discover payload.');
    final map = data.cast<String, dynamic>();
    return PlaceQueryResult(
      places: map
          .mapOrEmptyList('places')
          .map(Place.fromJson)
          .toList(),
      experiences: map
          .mapOrEmptyList('experiences')
          .map(Experience.fromJson)
          .toList(),
      interpretedQuery: map['interpreted_query']?.toString(),
    );
  }

  Map<String, dynamic> _toQuery(PlaceQuery query) => {
        if (query.text != null && query.text!.trim().isNotEmpty)
          'text': query.text,
        if (query.near != null) 'lat': query.near!.latitude,
        if (query.near != null) 'lng': query.near!.longitude,
        'radius_km': query.radiusKm,
        'limit': query.limit,
        if (query.categories.isNotEmpty)
          'categories': query.categories.map((c) => c.name).toList(),
        if (query.openAt != null)
          'open_at': query.openAt!.toIso8601String(),
        if (query.maxTypicalSpend != null)
          'max_spend': query.maxTypicalSpend,
      };

  static List<Place> _decodeList(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => Place.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
}

extension on Map<String, dynamic> {
  List<Map<String, dynamic>> mapOrEmptyList(String key) {
    final value = this[key];
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }
}

/// Kept for the WeatherProvider import chain; re-exported so callers do not
/// need to reach into the network layer.
typedef WeatherContext = ({WeatherSnapshot weather, TrafficSnapshot traffic});

/// Re-export used by context controllers.
typedef ActiveContext = DiscoveryContext;
