import 'dart:math' as math;

import '../../context/domain/context_models.dart';
import '../domain/place.dart';
import '../domain/place_repository.dart';
import 'local_experiences.dart';
import 'local_places.dart';

/// Offline implementation of [PlaceRepository] backed by the bundled dataset.
///
/// Implements the same contract as `RemotePlaceRepository`, including the
/// search, facet and distance semantics, so the UI behaves identically with
/// or without a backend.
class LocalPlaceRepository implements PlaceRepository {
  LocalPlaceRepository({this.latency = const Duration(milliseconds: 40)});

  /// Simulated I/O latency so loading states are exercised in development.
  final Duration latency;

  static final List<Place> _places = List.unmodifiable(localPlaces);
  static final List<Experience> _experiences = List.unmodifiable(
    localExperiences,
  );

  static Place? _placeById(String id) {
    for (final place in _places) {
      if (place.id == id) return place;
    }
    return null;
  }

  static Experience? _experienceById(String id) {
    for (final experience in _experiences) {
      if (experience.id == id) return experience;
    }
    return null;
  }

  /// Great-circle distance in km.
  static double _distance(GeoPoint a, GeoPoint b) {
    const earthRadiusKm = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final latA = _rad(a.latitude);
    final latB = _rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) * math.sin(dLng / 2) * math.cos(latA) * math.cos(latB);
    return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
  }

  static double _rad(double degrees) => degrees * math.pi / 180.0;

  Future<void> _latencyDelay() => Future<void>.delayed(latency);

  @override
  Future<List<Place>> search(PlaceQuery query) async {
    await _latencyDelay();
    return _places.where((place) => _matches(place, query)).toList();
  }

  @override
  Future<Place?> placeById(String id) async {
    await _latencyDelay();
    return _placeById(id);
  }

  @override
  Future<List<Experience>> experiencesForPlace(String placeId) async {
    await _latencyDelay();
    return _experiences.where((e) => e.placeId == placeId).toList();
  }

  @override
  Future<Experience?> experienceById(String id) async {
    await _latencyDelay();
    return _experienceById(id);
  }

  @override
  Future<List<Place>> popularNearby({
    required GeoPoint near,
    double radiusKm = 6,
    int limit = 12,
  }) async {
    await _latencyDelay();
    final nearby = _places
        .where((p) => _distance(near, p.centre) <= radiusKm)
        .toList();
    // Composite of footfall and quality, with proximity as the tie-breaker.
    nearby.sort((a, b) {
      final aScore = _popularity(a) - _distance(near, a.centre) * 0.35;
      final bScore = _popularity(b) - _distance(near, b.centre) * 0.35;
      return bScore.compareTo(aScore);
    });
    return nearby.take(limit).toList();
  }

  @override
  Future<List<Place>> localGems({
    required GeoPoint near,
    double radiusKm = 8,
    int limit = 12,
  }) async {
    await _latencyDelay();
    final candidates = <({Place place, double score})>[];
    for (final place in _places) {
      if (!place.localFavourite) continue;
      final distance = _distance(near, place.centre);
      if (distance > radiusKm) continue;
      final best = _experiences
          .where((e) => e.placeId == place.id)
          .fold<double>(0, (max, e) => math.max(max, e.localScore));
      candidates.add((place: place, score: best - distance * 1.2));
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(limit).map((c) => c.place).toList();
  }

  @override
  Future<PlaceQueryResult> discover(PlaceQuery query) async {
    await _latencyDelay();
    final places = _places.where((p) => _matches(p, query)).toList();
    final placeIds = places.map((p) => p.id).toSet();
    final experiences = _experiences
        .where((e) => placeIds.contains(e.placeId))
        .where((e) => query.categories.isEmpty ||
            query.categories.contains(e.category))
        .toList();
    return PlaceQueryResult(
      places: places,
      experiences: experiences,
      interpretedQuery: query.text,
    );
  }

  /// Normalised popularity, saturating so mega-attraction review counts do
  /// not permanently dominate the "popular" rail.
  static double _popularity(Place place) {
    final logReviews = math.log(place.reviewCount + 1) / math.log(1000);
    return (logReviews * 0.6 + place.rating * 0.4) * 10;
  }

  bool _matches(Place place, PlaceQuery query) {
    if (query.near != null &&
        _distance(query.near!, place.centre) > query.radiusKm) {
      return false;
    }
    if (query.categories.isNotEmpty && !query.categories.contains(place.category)) {
      // A place can still qualify via one of its experiences.
      final viaExperience = _experiences.any(
        (e) => e.placeId == place.id && query.categories.contains(e.category),
      );
      if (!viaExperience) return false;
    }
    if (query.maxTypicalSpend != null &&
        place.typicalSpend > query.maxTypicalSpend! &&
        place.typicalSpend != 0) {
      return false;
    }
    if (query.openAt != null && !place.openingHours.isOpenAt(query.openAt!)) {
      return false;
    }
    final text = query.text?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return true;
    final tokens = _tokenise(text);
    if (tokens.isEmpty) return true;
    final haystack =
        '${place.name} ${place.area} ${place.category.label} ${place.summary ?? ''}'
            .toLowerCase();
    return tokens.any(haystack.contains);
  }

  /// Cheap intent extraction from a natural-language query. Shared with the
  /// assistant so both interpret the same sentence the same way.
  static List<String> _tokenise(String text) {
    const stop = {
      'i', 'have', 'got', 'with', 'and', 'the', 'a', 'an', 'in', 'on', 'at',
      'to', 'for', 'of', 'my', 'me', 'some', 'any', 'want', 'need', 'looking',
      'show', 'give', 'find', 'something', 'please', 'around', 'near', 'rupees',
      'hours', 'hour', 'mins', 'minutes', 'minute', 'rs',
    };
    return text
        .split(RegExp(r'[^a-z0-9₹]+'))
        .where((t) => t.length > 2 && !stop.contains(t))
        .toList();
  }
}

