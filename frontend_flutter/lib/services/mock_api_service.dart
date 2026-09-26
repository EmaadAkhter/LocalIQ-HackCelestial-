import 'dart:math' as math;

import '../core/utils/geo.dart';
import '../data/mock_places.dart';
import '../models/chat_message.dart';
import '../models/itinerary.dart';
import '../models/place.dart';
import '../models/recommendation.dart';
import '../models/search_params.dart';
import 'api_service.dart';

/// Fully local implementation used while the backend is not connected.
///
/// It mirrors the FastAPI recommender (Phase A feasibility → Phase B ranking)
/// so the numbers the UI shows today match what the API returns later.
class MockApiService implements ApiService {
  MockApiService({this.latency = const Duration(milliseconds: 420)});

  final Duration latency;

  static const int bufferMinutes = 20;
  static const double maxDistanceKm = 30;
  static const String weather = 'Partly cloudy, 30°C';

  static const List<String> defaultSuggestions = <String>[
    'Indoor options',
    'Cheaper options',
    'Only food places',
  ];

  /// Simulated network delay.
  ///
  /// `Duration.zero` resolves on a microtask instead of scheduling a timer, so
  /// widget tests can `await` API calls without pumping the clock.
  Future<void> _wait() {
    if (latency <= Duration.zero) return Future<void>.value();
    return Future<void>.delayed(latency);
  }

  @override
  Future<List<Place>> listPlaces() async {
    await _wait();
    return MockPlaces.all;
  }

  @override
  Future<Place?> placeById(String id, {double? lat, double? lng}) async {
    await _wait();
    final Place? place = MockPlaces.byId(id);
    if (place == null) return null;
    if (lat == null || lng == null) return place;
    // Offline stand-in for the backend's /detail payload.
    return place.copyWithDistance(
      distanceKm: place.distanceFrom(lat, lng),
      travelMinutes: place.travelFrom(lat, lng),
    );
  }

  @override
  Future<String> weatherSummary() async {
    await _wait();
    return weather;
  }

  // -------------------------------------------------------------------------
  // Recommendation engine (synchronous core, async wrapper)
  // -------------------------------------------------------------------------

  List<Recommendation> rank(SearchParams params, {DateTime? at}) {
    final DateTime now =
        at ??
        (params.startTime == null
            ? DateTime.now()
            : _atTime(params.startTime!, DateTime.now()));
    final int windowMinutes = (params.timeHours * 60).round();

    final List<Recommendation> feasible = <Recommendation>[];
    for (final Place place in MockPlaces.all) {
      final double distanceKm = place.distanceFrom(params.latitude, params.longitude);
      final int travel = Geo.travelMinutes(distanceKm);
      final int totalMinutes = place.durationMin + travel * 2 + bufferMinutes;

      // --- Phase A: hard constraints (fail => not shown) ---
      if (place.avgCost > params.budgetInr) continue;
      if (totalMinutes > windowMinutes) continue;
      if (!place.isOpenAt(now)) continue;
      if (params.accessibility && !place.isWheelchairFriendly) continue;
      if (distanceKm > maxDistanceKm) continue;

      feasible.add(
        Recommendation(
          place: place,
          score: _score(place, params, distanceKm),
          distanceKm: distanceKm,
          travelMinutes: travel,
          totalMinutes: totalMinutes,
          estimatedCost: place.avgCost,
          whyItFits: _whyItFits(place, params, distanceKm),
          reasons: _reasons(place, params),
        ),
      );
    }

    feasible.sort(
      (Recommendation a, Recommendation b) => b.score.compareTo(a.score),
    );
    return feasible;
  }

  @override
  Future<RecommendationResult> recommend(SearchParams params) async {
    await _wait();
    return RecommendationResult(
      items: rank(params),
      totalCandidates: MockPlaces.all.length,
      weatherSummary: weather,
    );
  }

  /// Phase B: explicit weights, max 100.
  double _score(Place place, SearchParams params, double distanceKm) {
    double score = 0;

    // Interest match (0-30)
    score += params.interests.contains(place.category) ? 30 : 8;

    // Time fit (0-20)
    final double ratio =
        place.durationMin / math.max(1.0, params.timeHours * 60);
    score += ratio <= 0.85 ? 20 : math.max(4.0, 20 - (ratio - 0.85) * 40);

    // Budget fit (0-15)
    final double costRatio = params.budgetInr == 0
        ? 1.0
        : place.avgCost / params.budgetInr;
    score += costRatio <= 0.4 ? 15.0 : (costRatio <= 0.8 ? 11.0 : 7.0);

    // Distance (0-15)
    score += math.max(0.0, 15 - distanceKm * 0.9);

    // Rating (0-12)
    score += math.max(0.0, math.min(12.0, (place.rating - 3) * 8));

    // Local gem (0-8)
    score += math.min(8.0, place.localGemScore * 8);

    return double.parse(score.toStringAsFixed(2));
  }

  String _whyItFits(Place place, SearchParams params, double distanceKm) {
    final area = params.location.split(',').first.trim();
    final parts = <String>[
      'Fits your ${_inr(params.budgetInr)} budget',
      '${place.durationMin} min fits your ${_hours(params.timeHours)} window',
    ];
    if (params.interests.contains(place.category)) {
      parts.add(
        'matches your interest in ${place.category.label.toLowerCase()}',
      );
    }
    if (distanceKm < 1.5) {
      parts.add('right around $area');
    } else {
      parts.add('${distanceKm.toStringAsFixed(1)} km away');
    }
    parts.add('rated ${place.rating.toStringAsFixed(1)}★');
    return '${parts.join(' · ')}.';
  }

  List<String> _reasons(Place place, SearchParams params) {
    final reasons = <String>[];
    if (place.avgCost <= params.budgetInr) {
      reasons.add('Fits your budget (${_inr(params.budgetInr)})');
    }
    if (place.durationMin <= params.timeHours * 60) {
      reasons.add('Works inside your ${_hours(params.timeHours)} window');
    }
    if ((params.groupType == GroupType.family ||
            params.groupType == GroupType.couple) &&
        place.isStepFree) {
      reasons.add('Step-free and easy for families');
    }
    if (place.rating >= 4.5) {
      reasons.add('Highly rated (${place.rating.toStringAsFixed(1)}★)');
    }
    if (place.localGemScore >= 0.85) reasons.add('A genuine local gem');
    if (place.isWheelchairFriendly) reasons.add('Wheelchair accessible');
    if (place.indoorOutdoor == IndoorOutdoor.indoor) {
      reasons.add('Indoor, so rain or heat will not ruin the plan');
    }
    reasons.add('Close to other recommended places');
    return reasons.take(5).toList();
  }

  // -------------------------------------------------------------------------
  // Natural-language parsing (mock)
  // -------------------------------------------------------------------------

  @override
  Future<SearchParams> parseQuery(String text, SearchParams current) async {
    await _wait();
    final String lower = text.toLowerCase();
    SearchParams next = current;

    final RegExpMatch? budget = RegExp(
      r'(?:rs\.?|inr|₹)\s*([\d,]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (budget != null) {
      next = next.copyWith(
        budgetInr: int.parse(budget.group(1)!.replaceAll(',', '')),
      );
    }

    final RegExpMatch? hours = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h\b)',
    ).firstMatch(lower);
    if (hours != null) {
      final double? value = double.tryParse(hours.group(1)!);
      if (value != null) next = next.copyWith(timeHours: value);
    }

    const Map<String, String> areas = <String, String>{
      'bandra': 'Bandra, Mumbai',
      'colaba': 'Colaba, Mumbai',
      'juhu': 'Juhu, Mumbai',
      'andheri': 'Andheri, Mumbai',
      'powai': 'Powai, Mumbai',
      'fort': 'Fort, Mumbai',
      'dadar': 'Dadar, Mumbai',
    };
    areas.forEach((String key, String value) {
      if (lower.contains(key)) next = next.copyWith(location: value);
    });

    const Map<String, PlaceCategory> hints = <String, PlaceCategory>{
      'food': PlaceCategory.food,
      'eat': PlaceCategory.food,
      'cafe': PlaceCategory.food,
      'culture': PlaceCategory.culture,
      'heritage': PlaceCategory.culture,
      'temple': PlaceCategory.culture,
      'shopping': PlaceCategory.shopping,
      'market': PlaceCategory.shopping,
      'bazaar': PlaceCategory.shopping,
      'art': PlaceCategory.art,
      'gallery': PlaceCategory.art,
      'nightlife': PlaceCategory.nightlife,
      'bar': PlaceCategory.nightlife,
      'outdoor': PlaceCategory.outdoor,
      'beach': PlaceCategory.outdoor,
      'sunset': PlaceCategory.outdoor,
      'walk': PlaceCategory.outdoor,
    };
    final Set<PlaceCategory> interests = <PlaceCategory>{...next.interests};
    hints.forEach((String key, PlaceCategory value) {
      if (lower.contains(key)) interests.add(value);
    });
    if (interests.isNotEmpty) next = next.copyWith(interests: interests);

    if (lower.contains('wheelchair') ||
        lower.contains('step free') ||
        lower.contains('step-free') ||
        lower.contains('accessible')) {
      next = next.copyWith(accessibility: true);
    }

    if (lower.contains('family') || lower.contains('kids')) {
      next = next.copyWith(groupType: GroupType.family);
    } else if (lower.contains('couple') || lower.contains('date')) {
      next = next.copyWith(groupType: GroupType.couple);
    } else if (lower.contains('friend')) {
      next = next.copyWith(groupType: GroupType.friends);
    } else if (lower.contains('solo') || lower.contains('alone')) {
      next = next.copyWith(groupType: GroupType.solo);
    }

    return next.copyWith(query: text);
  }

  // -------------------------------------------------------------------------
  // Assistant (mock replies only)
  // -------------------------------------------------------------------------

  @override
  Future<ChatMessage> chat(ChatRequest request, SearchParams params) async {
    await _wait();
    final String q = request.message.toLowerCase();
    final List<Recommendation> pool = rank(params);

    List<Recommendation> pick(bool Function(Recommendation r) test) {
      return pool.where(test).toList();
    }

    if (q.contains('indoor') || q.contains('rain')) {
      final List<Recommendation> indoor = pick(
        (Recommendation r) => r.place.indoorOutdoor == IndoorOutdoor.indoor,
      );
      return ChatMessage(
        role: ChatRole.assistant,
        text: q.contains('rain')
            ? 'It is ${weather.toLowerCase()} in Mumbai, so I kept indoor stops '
                  'first. Sea-facing walks still work if the rain clears by 4 PM.'
            : 'Indoor options that still fit your ${_hours(params.timeHours)} '
                  'window and ${_inr(params.budgetInr)} budget:',
        placeChips: indoor.take(3).map((Recommendation r) => r.place).toList(),
        suggestions: defaultSuggestions,
      );
    }

    if (q.contains('cheap') || q.contains('budget') || q.contains('spend')) {
      final List<Recommendation> sorted = <Recommendation>[...pool]
        ..sort(
          (Recommendation a, Recommendation b) =>
              a.place.avgCost.compareTo(b.place.avgCost),
        );
      return ChatMessage(
        role: ChatRole.assistant,
        text: 'Cheapest picks that still respect your time and interests:',
        placeChips: sorted.take(3).map((Recommendation r) => r.place).toList(),
        suggestions: defaultSuggestions,
      );
    }

    if (q.contains('food') || q.contains('eat') || q.contains('hunger')) {
      return ChatMessage(
        role: ChatRole.assistant,
        text: 'Food stops within reach, ordered by how well they fit today:',
        placeChips: pick(
          (Recommendation r) => r.place.category == PlaceCategory.food,
        ).take(3).map((Recommendation r) => r.place).toList(),
        suggestions: defaultSuggestions,
      );
    }

    if (q.contains('family') || q.contains('kid') || q.contains('child')) {
      return ChatMessage(
        role: ChatRole.assistant,
        text:
            'Family-friendly and step-free, so nobody climbs stairs mid-plan:',
        placeChips: pick(
          (Recommendation r) => r.place.isStepFree,
        ).take(3).map((Recommendation r) => r.place).toList(),
        suggestions: defaultSuggestions,
      );
    }

    if (q.contains('time') || q.contains('how long') || q.contains('hour')) {
      return ChatMessage(
        role: ChatRole.assistant,
        text:
            'You have about ${_hours(params.timeHours)}. Two stops is the sweet '
            'spot — one main stop plus one nearby. A third only fits if it is '
            'under 30 minutes.',
        suggestions: const <String>['Show 2-stop plan', 'Show 3-stop plan'],
      );
    }

    return ChatMessage(
      role: ChatRole.assistant,
      text:
          'Based on ${_hours(params.timeHours)}, ${_inr(params.budgetInr)} and a '
          '${params.groupType.label.toLowerCase()} trip, these three work best '
          'right now:',
      placeChips: pool.take(3).map((Recommendation r) => r.place).toList(),
      suggestions: defaultSuggestions,
    );
  }

  // -------------------------------------------------------------------------
  // Itinerary
  // -------------------------------------------------------------------------

  @override
  Future<ItineraryPlan> buildItinerary({
    required List<Recommendation> recommendations,
    required SearchParams params,
  }) async {
    await _wait();
    final List<ItineraryStop> stops = <ItineraryStop>[];
    double cursorLat = params.latitude;
    double cursorLng = params.longitude;

    for (final Recommendation rec in recommendations.take(3)) {
      final int travel = Geo.travelMinutes(
        rec.place.distanceFrom(cursorLat, cursorLng),
      );
      stops.add(
        ItineraryStop(
          place: rec.place,
          visitMinutes: rec.place.durationMin,
          travelFromPreviousMinutes: travel,
        ),
      );
      cursorLat = rec.place.lat;
      cursorLng = rec.place.lng;
    }

    return ItineraryPlan(
      title: 'Your ${_planTitle(params.timeHours)}',
      stops: stops,
    ).withStartTimes();
  }

  static String _inr(int value) => '₹$value';

  static String _hours(double value) {
    final int h = value.round();
    return h == 1 ? '1 hour' : '$h hours';
  }

  static String _planTitle(double timeHours) {
    final int h = timeHours.round();
    return h == 1 ? '1-Hour Plan' : '$h-Hour Plan';
  }

  static DateTime _atTime(String hhmm, DateTime fallback) {
    final List<String> parts = hhmm.split(':');
    final int? h = int.tryParse(parts.first);
    if (h == null) return fallback;
    final int m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(fallback.year, fallback.month, fallback.day, h, m);
  }
}
