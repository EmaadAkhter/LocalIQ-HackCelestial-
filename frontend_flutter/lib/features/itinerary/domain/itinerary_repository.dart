import '../../recommendations/domain/recommendation.dart';
import 'itinerary.dart';

/// Mutations available on a plan. Mirrors the backend REST surface
/// (`POST /itineraries/{id}/stops`, `PATCH .../reorder`, ...).
abstract interface class ItineraryRepository {
  Future<Itinerary?> active();

  Future<Itinerary> create({
    required String userId,
    required String title,
    required String originLabel,
    required ({double lat, double lng}) origin,
  });

  Future<Itinerary> addStop({
    required Itinerary itinerary,
    required Recommendation recommendation,
  });

  Future<Itinerary> removeStop({
    required Itinerary itinerary,
    required String stopId,
  });

  /// Re-sequences stops. The implementation recomputes travel legs and
  /// clock times, so the UI never has to.
  Future<Itinerary> reorder({
    required Itinerary itinerary,
    required int oldIndex,
    required int newIndex,
  });

  /// Re-evaluates the whole plan against current weather, traffic and hours.
  Future<Itinerary> recheck({
    required Itinerary itinerary,
    required RecommendationEngineGateway gateway,
  });

  Future<Itinerary> save(Itinerary itinerary);

  Future<void> clear();

  /// Backing lookup so the UI can resolve stops to their live data.
  RecommendationEngineGateway get gateway;
}

/// Narrow seam so [ItineraryRepository] can re-check without importing the
/// full recommendation stack.
abstract interface class RecommendationEngineGateway {
  Future<TravelEstimate> travelBetween({
    required ({double lat, double lng}) from,
    required ({double lat, double lng}) to,
  });

  Future<bool> isOpenAt({
    required String placeId,
    required DateTime at,
  });
}
