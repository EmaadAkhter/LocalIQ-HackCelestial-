import '../models/chat_message.dart';
import '../models/itinerary.dart';
import '../models/place.dart';
import '../models/recommendation.dart';
import '../models/search_params.dart';

/// Contract between the UI and any data source.
///
/// [MockApiService] is wired up today; [FastApiService] implements the exact
/// same surface against the LocalIQ FastAPI backend, so swapping is a one-line
/// change in `app.dart`.
abstract class ApiService {
  /// All curated experiences.
  Future<List<Place>> listPlaces();

  /// Single experience, or null when not found.
  ///
  /// [lat]/[lng] are the caller's position so the backend can compute distance,
  /// travel time and route data. Passing them yields the enriched payload.
  Future<Place?> placeById(String id, {double? lat, double? lng});

  /// Feasibility + ranking for the given constraints.
  Future<RecommendationResult> recommend(SearchParams params);

  /// Natural-language → structured constraints (prefills Home).
  Future<SearchParams> parseQuery(String text, SearchParams current);

  /// Assistant turn. Implementations must never throw.
  Future<ChatMessage> chat(ChatRequest request, SearchParams params);

  /// Short weather blurb, e.g. "Partly cloudy, 30°C".
  Future<String> weatherSummary();

  /// Builds an ordered plan from ranked recommendations.
  Future<ItineraryPlan> buildItinerary({
    required List<Recommendation> recommendations,
    required SearchParams params,
  });
}
