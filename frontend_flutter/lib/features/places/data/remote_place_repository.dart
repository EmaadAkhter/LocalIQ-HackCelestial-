import '../../../core/error/app_exception.dart';
import '../../../core/network/json_api_client.dart';
import '../../../core/utils/json_map_x.dart';
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
///   GET /places/for-you?lat=&lng=&limit=
///   GET /places/right-now?lat=&lng=&limit=
///   GET /places/gems?lat=&lng=&limit=
///   GET /places/discover?text=...
class RemotePlaceRepository implements PlaceRepository {
  RemotePlaceRepository(this._client);

  final JsonApiClient _client;

  /// Server-side page cap (app/api/v1/place_discovery.py): `limit` above this
  /// is rejected with a 422, so requests are paged rather than enlarged.
  static const int _maxPageSize = 100;

  @override
  Future<List<Place>> search(PlaceQuery query) async {
    // `limit <= 0` means "the whole catalogue": keep walking offset pages until
    // the server stops returning rows. Otherwise stop at the caller's limit.
    final unbounded = query.limit < 1;
    final places = <Place>[];
    var offset = 0;
    while (unbounded || places.length < query.limit) {
      final pageSize = unbounded
          ? _maxPageSize
          : (query.limit - places.length).clamp(1, _maxPageSize);
      final data = await _client.get(
        '/places',
        query: {..._toQuery(query), 'limit': pageSize, 'offset': offset},
      );
      if (data is! List) {
        if (offset == 0) {
          throw const ParseException('Unexpected /places payload.');
        }
        break;
      }
      final page = data
          .whereType<Map>()
          .map((e) => Place.fromJson(e.cast<String, dynamic>()))
          .toList();
      places.addAll(page);
      if (page.length < pageSize) break; // last page reached
      offset += page.length;
    }
    return places;
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
  Future<List<Place>> forYou({GeoPoint? near, int limit = 12}) async {
    final data = await _client.get(
      '/places/for-you',
      query: {
        if (near != null) 'lat': near.latitude,
        if (near != null) 'lng': near.longitude,
        'limit': limit,
      },
    );
    return _decodeList(data);
  }

  @override
  Future<List<Place>> rightNow({GeoPoint? near, int limit = 12}) async {
    final data = await _client.get(
      '/places/right-now',
      query: {
        if (near != null) 'lat': near.latitude,
        if (near != null) 'lng': near.longitude,
        'limit': limit,
      },
    );
    return _decodeList(data);
  }

  @override
  Future<List<Place>> localGems({GeoPoint? near, int limit = 12}) async {
    final data = await _client.get(
      '/places/gems',
      query: {
        if (near != null) 'lat': near.latitude,
        if (near != null) 'lng': near.longitude,
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

  @override
  Future<List<Place>> searchRemote(
    String query, {
    GeoPoint? near,
    int limit = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final data = await _client.get(
        '/places/search',
        query: {
          'q': trimmed,
          if (near != null) 'lat': near.latitude,
          if (near != null) 'lng': near.longitude,
          'limit': limit,
        },
      );
      if (data is! Map) return const [];
      return (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Place.fromSearchResult(e.cast<String, dynamic>()))
          .toList();
    } on AppException {
      // Search is best-effort: a Google outage must not blank the screen.
      return const [];
    }
  }

  Map<String, dynamic> _toQuery(PlaceQuery query) => {
        if (query.text != null && query.text!.trim().isNotEmpty)
          'text': query.text,
        if (query.near != null) 'lat': query.near!.latitude,
        if (query.near != null) 'lng': query.near!.longitude,
        'radius_km': query.radiusKm,
        'limit': query.limit.clamp(1, _maxPageSize),
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

/// Kept for the WeatherProvider import chain; re-exported so callers do not
/// need to reach into the network layer.
typedef WeatherContext = ({WeatherSnapshot weather, TrafficSnapshot traffic});

/// Re-export used by context controllers.
typedef ActiveContext = DiscoveryContext;
