import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import '../models/chat_message.dart';
import '../models/itinerary.dart';
import '../models/place.dart';
import '../models/recommendation.dart';
import '../models/search_params.dart';
import 'api_service.dart';
import 'mock_api_service.dart';

/// Real client for the LocalIQ FastAPI backend.
///
/// This is the only place the app talks to. All recommendation, Places and
/// Routes work happens server-side — the client just renders what comes back.
///
/// **No Google key is ever sent or received here.** The backend holds the
/// server-restricted Places/Routes keys; the app only receives LocalIQ URLs
/// (e.g. `/api/v1/images/place?...` photo proxy). Client map keys are a
/// separate concern handled by [AppConfig] / `/api/v1/config`.
///
/// Every method degrades to [MockApiService] on any error, so the UI keeps
/// working when the backend is down.
class FastApiService implements ApiService {
  FastApiService({
    String? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
    MockApiService? fallback,
  })  : baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _fallback = fallback ?? MockApiService();

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;
  final MockApiService _fallback;

  /// Absolute URL for an image path returned by the backend (photo proxy).
  String assetUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$baseUrl$path';
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final Map<String, String>? params = query
        ?.map((String k, dynamic v) => MapEntry<String, String>(k, '$v'));
    return Uri.parse('$baseUrl$path').replace(queryParameters: params);
  }

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    final http.Response res = await _client
        .get(_uri(path, query), headers: const <String, String>{'Accept': 'application/json'})
        .timeout(timeout);
    if (res.statusCode >= 400) {
      throw http.ClientException('GET $path failed: ${res.statusCode}');
    }
    return jsonDecode(res.body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final http.Response res = await _client
        .post(
          _uri(path),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (res.statusCode >= 400) {
      throw http.ClientException('POST $path failed: ${res.statusCode}');
    }
    return jsonDecode(res.body);
  }

  // -------------------------------------------------------------------------
  // Places / experiences
  // -------------------------------------------------------------------------

  @override
  Future<List<Place>> listPlaces() async {
    try {
      final dynamic data = await _get(
        '/api/v1/experiences',
        <String, dynamic>{'limit': 200},
      );
      final List<dynamic> items =
          (data as Map<String, dynamic>)['items'] as List<dynamic>? ??
              <dynamic>[];
      return items
          .map((dynamic e) => Place.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _fallback.listPlaces();
    }
  }

  @override
  Future<Place?> placeById(String id, {double? lat, double? lng}) async {
    try {
      // `/detail` returns the enriched payload (distance, hours, weather, route).
      // Distance/travel time are computed server-side; the client only passes
      // its current position so the backend can calculate them.
      final dynamic data =
          await _get('/api/v1/experiences/$id/detail', <String, dynamic>{
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });
      return Place.fromDetail(data as Map<String, dynamic>);
    } catch (_) {
      return _fallback.placeById(id);
    }
  }

  /// Place discovery via the backend's Google Places integration.
  ///
  /// The backend normalizes Google into LocalIQ shapes and falls back to SQLite
  /// when Google is unavailable, so this returns data either way.
  Future<RecommendationResult> searchPlaces(
    String query, {
    double? lat,
    double? lng,
    int limit = 10,
  }) async {
    try {
      final dynamic data = await _get('/api/v1/places/search', <String, dynamic>{
        'q': query,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'limit': limit,
      });
      final Map<String, dynamic> map = data as Map<String, dynamic>;
      final List<dynamic> items = map['items'] as List<dynamic>? ?? <dynamic>[];
      return RecommendationResult(
        items: items
            .map((dynamic e) => Place.fromPlaceSearch(e as Map<String, dynamic>))
            .map(
              (Place p) => Recommendation(
                place: p,
                score: p.rating,
                distanceKm: p.distanceKm ?? 0,
                travelMinutes: p.travelMinutes ?? 0,
                totalMinutes: p.durationMin,
                estimatedCost: p.avgCost,
                whyItFits: p.description.isEmpty ? p.blurb : p.description,
                reasons: <String>[p.blurb],
                routeSource: 'local',
              ),
            )
            .toList(),
        totalCandidates: (map['count'] as num?)?.round() ?? 0,
        weatherSummary: null,
        routeSource: 'local',
        usedFallback: map['fallback'] as bool? ?? true,
      );
    } catch (_) {
      return RecommendationResult(
        items: const <Recommendation>[],
        totalCandidates: 0,
        usedFallback: true,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Recommendations
  // -------------------------------------------------------------------------

  @override
  Future<RecommendationResult> recommend(SearchParams params) async {
    try {
      final dynamic data = await _post('/api/v1/recommend', params.toApiJson());
      final Map<String, dynamic> map = data as Map<String, dynamic>;
      final List<dynamic> raw =
          map['recommendations'] as List<dynamic>? ?? <dynamic>[];
      return RecommendationResult(
        items: raw
            .map((dynamic e) =>
                Recommendation.fromApiJson(e as Map<String, dynamic>))
            .toList(),
        totalCandidates: (map['total_candidates'] as num?)?.round() ?? 0,
        weatherSummary: map['weather_summary'] as String?,
        routeSource: '${map['route_source'] ?? 'local'}',
      );
    } catch (_) {
      return _fallback.recommend(params);
    }
  }

  @override
  Future<SearchParams> parseQuery(String text, SearchParams current) async {
    try {
      final dynamic data =
          await _post('/api/v1/parse', <String, dynamic>{'text': text});
      final Map<String, dynamic> c =
          (data as Map<String, dynamic>)['constraints'] as Map<String, dynamic>;
      final String? group = c['group_type'] as String?;
      return current.copyWith(
        query: text,
        location: c['location'] as String? ?? current.location,
        timeHours: (c['time_hours'] as num?)?.toDouble() ?? current.timeHours,
        budgetInr: (c['budget_inr'] as num?)?.round() ?? current.budgetInr,
        groupType: group == null
            ? current.groupType
            : GroupType.fromLabel(group),
        interests: (c['interests'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => PlaceCategory.fromLabel('$e'))
            .toSet(),
        accessibility: c['accessibility'] != null,
      );
    } catch (_) {
      return _fallback.parseQuery(text, current);
    }
  }

  @override
  Future<ChatMessage> chat(ChatRequest request, SearchParams params) async {
    try {
      final dynamic data = await _post('/api/v1/chat', request.toApiJson());
      final Map<String, dynamic> map = data as Map<String, dynamic>;
      return ChatMessage(
        role: ChatRole.assistant,
        text: '${map['reply'] ?? ''}',
        suggestions: const <String>[
          'Indoor options',
          'Cheaper options',
          'Only food places',
        ],
      );
    } catch (_) {
      return _fallback.chat(request, params);
    }
  }

  @override
  Future<String> weatherSummary() async {
    try {
      final dynamic data = await _get('/api/v1/weather');
      final Map<String, dynamic> map = data as Map<String, dynamic>;
      if (map['available'] == true) return '${map['description'] ?? ''}';
      return 'Weather unavailable';
    } catch (_) {
      return _fallback.weatherSummary();
    }
  }

  @override
  Future<ItineraryPlan> buildItinerary({
    required List<Recommendation> recommendations,
    required SearchParams params,
  }) async {
    // Sequencing is client-side for now; the backend has no itinerary endpoint.
    return _fallback.buildItinerary(
      recommendations: recommendations,
      params: params,
    );
  }

  void dispose() => _client.close();
}
