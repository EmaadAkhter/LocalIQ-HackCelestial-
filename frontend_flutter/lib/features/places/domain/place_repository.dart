import '../../../core/error/app_exception.dart';
import '../../context/domain/context_models.dart';
import '../../places/domain/place.dart';

/// Paginated envelope shared by list endpoints.
class Paged<T> {
  const Paged({required this.items, required this.total, this.nextCursor});

  final List<T> items;
  final int total;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Query inputs for a places search.
class PlaceQuery {
  const PlaceQuery({
    this.text,
    this.near,
    this.categories = const {},
    this.radiusKm = 12,
    this.limit = 40,
    this.openAt,
    this.maxTypicalSpend,
  });

  final String? text;
  final GeoPoint? near;
  final Set<ExperienceCategory> categories;
  final double radiusKm;

  /// Maximum results to return. `0` (or negative) means "no limit" — used for
  /// catalogue loads that want everything, not a proximity search.
  final int limit;
  final DateTime? openAt;
  final int? maxTypicalSpend;

  PlaceQuery copyWith({
    String? text,
    GeoPoint? near,
    Set<ExperienceCategory>? categories,
    double? radiusKm,
    int? limit,
    DateTime? openAt,
    int? maxTypicalSpend,
  }) {
    return PlaceQuery(
      text: text ?? this.text,
      near: near ?? this.near,
      categories: categories ?? this.categories,
      radiusKm: radiusKm ?? this.radiusKm,
      limit: limit ?? this.limit,
      openAt: openAt ?? this.openAt,
      maxTypicalSpend: maxTypicalSpend ?? this.maxTypicalSpend,
    );
  }
}

/// Read access to places and experiences.
///
/// Implementations: [RemotePlaceRepository] (backend) and
/// [LocalPlaceRepository] (bundled dataset). The UI only sees this interface.
abstract interface class PlaceRepository {
  Future<List<Place>> search(PlaceQuery query);

  Future<Place?> placeById(String id);

  Future<List<Experience>> experiencesForPlace(String placeId);

  Future<Experience?> experienceById(String id);

  /// Popular places in an area, ranked by a composite of footfall, rating
  /// and recency — never used as the sole basis for LocalIQ ranking.
  Future<List<Place>> popularNearby({
    required GeoPoint near,
    double radiusKm = 6,
    int limit = 12,
  });

  /// "Recommended for you": taste-ranked places for the signed-in user.
  ///
  /// Anonymous callers get the deterministic quality/distance ranking, so the
  /// rail is never empty. [near] is optional — without it the backend ranks the
  /// whole catalogue.
  Future<List<Place>> forYou({GeoPoint? near, int limit = 12});

  /// "Perfect right now": places ranked by the live moment (weather, time of
  /// day, crowd). Deliberately distinct from [forYou].
  Future<List<Place>> rightNow({GeoPoint? near, int limit = 12});

  /// Places locals rate highly but that sit below the tourist threshold.
  ///
  /// Only genuine gems are returned (the backend applies a floor); [near] is
  /// optional for a city-wide list.
  Future<List<Place>> localGems({GeoPoint? near, int limit = 12});

  /// Full-text + faceted search backing natural-language queries.
  Future<PlaceQueryResult> discover(PlaceQuery query);

  /// Real place lookup for free-text queries, backed by Google Places via
  /// `GET /places/search`. Returns an empty list when the remote lookup is
  /// unavailable so callers can fall back to the local catalogue.
  Future<List<Place>> searchRemote(
    String query, {
    GeoPoint? near,
    int limit = 10,
  });
}

class PlaceQueryResult {
  const PlaceQueryResult({
    required this.places,
    required this.experiences,
    this.interpretedQuery,
  });

  final List<Place> places;
  final List<Experience> experiences;

  /// What the engine understood the user's sentence to mean.
  final String? interpretedQuery;
}

/// Live conditions and traffic.
abstract interface class ContextRepository {
  Future<WeatherSnapshot> weatherAt(GeoPoint point);

  Future<TrafficSnapshot> trafficAt(GeoPoint point);

  /// Combined round trip so the UI makes one call instead of two.
  Future<({WeatherSnapshot weather, TrafficSnapshot traffic})> liveContext(
    GeoPoint point,
  );
}

/// Errors surface as [AppException] subclasses from every repository.
typedef Result<T> = Future<T>;
