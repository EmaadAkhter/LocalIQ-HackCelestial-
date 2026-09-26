import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/itinerary.dart';
import '../models/place.dart';
import '../models/recommendation.dart';
import '../models/search_params.dart';
import '../services/api_service.dart';

/// Single source of truth for search, recommendations and the itinerary.
///
/// Injected via `provider` and read with `context.watch<AppState>()`.
class AppState extends ChangeNotifier {
  // A private *named* parameter is illegal in Dart, so the public `api` name
  // has to be mapped onto the private field explicitly.
  // ignore: prefer_initializing_formals
  AppState({required ApiService api}) : _api = api;

  final ApiService _api;

  // ---------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------
  SearchParams _params = const SearchParams();
  SearchParams get params => _params;

  String _queryDraft = '';
  String get queryDraft => _queryDraft;

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  // ---------------------------------------------------------------------
  // Recommendations
  // ---------------------------------------------------------------------
  List<Recommendation> _recommendations = <Recommendation>[];
  List<Recommendation> get recommendations => _recommendations;

  List<Recommendation> _allRecommendations = <Recommendation>[];
  int _totalCandidates = 0;
  int get totalCandidates => _totalCandidates;

  String? _weatherSummary;
  String? get weatherSummary => _weatherSummary;

  SortOption _sort = SortOption.recommended;
  SortOption get sort => _sort;

  FilterOptions _filters = const FilterOptions();
  FilterOptions get filters => _filters;

  bool get hasSearched => _hasSearched;
  bool _hasSearched = false;

  // ---------------------------------------------------------------------
  // Itinerary
  // ---------------------------------------------------------------------
  final List<Recommendation> _itineraryStops = <Recommendation>[];
  List<Recommendation> get itineraryStops => List<Recommendation>.unmodifiable(_itineraryStops);

  ItineraryPlan? _plan;
  ItineraryPlan? get plan => _plan;

  bool _isBuildingPlan = false;
  bool get isBuildingPlan => _isBuildingPlan;

  // ---------------------------------------------------------------------
  // Favourites / profile
  // ---------------------------------------------------------------------
  final Set<String> _favourites = <String>{};
  Set<String> get favourites => Set<String>.unmodifiable(_favourites);

  int get visitCount => _visits;
  int _visits = 12;

  String get displayName => 'Guest Explorer';
  bool get isGuest => true;

  // ---------------------------------------------------------------------
  // Home mutations
  // ---------------------------------------------------------------------

  void setQueryDraft(String value) {
    _queryDraft = value;
    notifyListeners();
  }

  void setTimeHours(double value) {
    _params = _params.copyWith(timeHours: value);
    notifyListeners();
  }

  void setBudget(int value) {
    _params = _params.copyWith(budgetInr: value);
    notifyListeners();
  }

  void toggleInterest(PlaceCategory category) {
    final Set<PlaceCategory> next = <PlaceCategory>{..._params.interests};
    if (!next.remove(category)) next.add(category);
    _params = _params.copyWith(interests: next);
    notifyListeners();
  }

  void setGroupType(GroupType type) {
    _params = _params.copyWith(groupType: type);
    notifyListeners();
  }

  void setInterests(Set<PlaceCategory> interests) {
    _params = _params.copyWith(interests: interests);
    notifyListeners();
  }

  void toggleAccessibility() {
    _params = _params.copyWith(accessibility: !_params.accessibility);
    notifyListeners();
  }

  void setLocation(String label, double lat, double lng) {
    _params = _params.copyWith(location: label, latitude: lat, longitude: lng);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Search + recommendation
  // ---------------------------------------------------------------------

  /// Parses the natural-language box then runs the recommendation flow.
  Future<void> findExperiences() async {
    _isSearching = true;
    notifyListeners();
    try {
      final String draft = _queryDraft.trim();
      if (draft.isNotEmpty) {
        _params = await _api.parseQuery(draft, _params);
      }
      final RecommendationResult result = await _api.recommend(_params);
      _allRecommendations = result.items;
      _totalCandidates = result.totalCandidates;
      _weatherSummary = result.weatherSummary;
      _hasSearched = true;
      _visits++;
      _applyView();
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Re-runs the current search (used by "What-if" changes).
  Future<void> refresh() async {
    _params = _params.copyWith(timeHours: _params.timeHours);
    await findExperiences();
  }

  void setSort(SortOption option) {
    _sort = option;
    _applyView();
    notifyListeners();
  }

  void setFilters(FilterOptions value) {
    _filters = value;
    _applyView();
    notifyListeners();
  }

  void clearFilters() {
    _filters = const FilterOptions();
    _applyView();
    notifyListeners();
  }

  void _applyView() {
    List<Recommendation> items = _allRecommendations.where((Recommendation r) {
      final FilterOptions f = _filters;
      if (f.maxCost != null && r.place.avgCost > f.maxCost!) return false;
      if (f.maxTravelMinutes != null && r.travelMinutes > f.maxTravelMinutes!) {
        return false;
      }
      if (f.indoorOnly && r.place.indoorOutdoor != IndoorOutdoor.indoor) {
        return false;
      }
      if (f.openOnly && !r.place.isOpenAt(DateTime.now())) return false;
      return true;
    }).toList();

    switch (_sort) {
      case SortOption.recommended:
        items.sort((Recommendation a, Recommendation b) => b.score.compareTo(a.score));
        break;
      case SortOption.rating:
        items.sort((Recommendation a, Recommendation b) => b.place.rating.compareTo(a.place.rating));
        break;
      case SortOption.distance:
        items.sort((Recommendation a, Recommendation b) => a.distanceKm.compareTo(b.distanceKm));
        break;
      case SortOption.costLowToHigh:
        items.sort((Recommendation a, Recommendation b) => a.place.avgCost.compareTo(b.place.avgCost));
        break;
      case SortOption.durationShortest:
        items.sort((Recommendation a, Recommendation b) => a.place.durationMin.compareTo(b.place.durationMin));
        break;
    }
    _recommendations = items;
  }

  // ---------------------------------------------------------------------
  // Explore tab navigation (Home <-> Results, keeps bottom nav visible)
  // ---------------------------------------------------------------------

  /// 0 = Home/Search, 1 = Recommendations.
  int get exploreIndex => _exploreIndex;
  int _exploreIndex = 0;

  void showHome() {
    _exploreIndex = 0;
    notifyListeners();
  }

  void showResults() {
    _exploreIndex = 1;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Favourites
  // ---------------------------------------------------------------------

  bool isFavourite(String placeId) => _favourites.contains(placeId);

  void toggleFavourite(String placeId) {
    if (!_favourites.remove(placeId)) _favourites.add(placeId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Itinerary
  // ---------------------------------------------------------------------

  bool isInItinerary(String placeId) =>
      _itineraryStops.any((Recommendation r) => r.place.id == placeId);

  void addToItinerary(Recommendation rec) {
    if (isInItinerary(rec.place.id)) return;
    if (_itineraryStops.length >= 5) return;
    _itineraryStops.add(rec);
    _plan = null;
    notifyListeners();
  }

  /// Adds a place that is not (yet) in the ranked list, e.g. from Place Details.
  ///
  /// Distance and travel time are *not* recomputed here: the client never does
  /// routing maths. It reuses whatever the backend already returned on the
  /// detail/recommend payload.
  void addPlaceToItinerary(Place place) {
    if (isInItinerary(place.id)) return;
    if (_itineraryStops.length >= 5) return;
    final int travel = place.travelMinutes ?? 0;
    addToItinerary(
      Recommendation(
        place: place,
        score: 0,
        distanceKm: place.distanceKm ?? 0,
        travelMinutes: travel,
        totalMinutes: place.durationMin + travel * 2 + 20,
        estimatedCost: place.avgCost,
        whyItFits: 'Added by you',
        reasons: const <String>[],
      ),
    );
  }

  void removeFromItinerary(String placeId) {
    _itineraryStops.removeWhere((Recommendation r) => r.place.id == placeId);
    _plan = null;
    notifyListeners();
  }

  /// Handles a drag-reorder. [newIndex] already accounts for the removed item
  /// (ReorderableListView.onReorderItem semantics).
  void moveStop(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _itineraryStops.length) return;
    final int target = newIndex.clamp(0, _itineraryStops.length - 1);
    if (target == oldIndex) return;
    final Recommendation item = _itineraryStops.removeAt(oldIndex);
    _itineraryStops.insert(target, item);
    _plan = null;
    notifyListeners();
  }

  void clearItinerary() {
    _itineraryStops.clear();
    _plan = null;
    notifyListeners();
  }

  /// Builds (or rebuilds) the ordered plan from the current stops.
  Future<void> buildPlan() async {
    if (_itineraryStops.isEmpty) return;
    _isBuildingPlan = true;
    notifyListeners();
    try {
      _plan = await _api.buildItinerary(
        recommendations: _itineraryStops,
        params: _params,
      );
    } finally {
      _isBuildingPlan = false;
      notifyListeners();
    }
  }

  void savePlan() {
    final ItineraryPlan? current = _plan;
    if (current == null) return;
    _plan = current.copyWith(savedAt: DateTime.now());
    notifyListeners();
  }

  /// Adds the top ranked recommendation to the plan (quick action).
  void addTopRecommendation() {
    if (_recommendations.isEmpty) return;
    addToItinerary(_recommendations.first);
  }

  // ---------------------------------------------------------------------
  // Chat
  // ---------------------------------------------------------------------

  Future<ChatMessage> sendChat(ChatRequest request) {
    return _api.chat(request, _params);
  }

  void reset() {
    _params = const SearchParams();
    _queryDraft = '';
    _recommendations = <Recommendation>[];
    _allRecommendations = <Recommendation>[];
    _totalCandidates = 0;
    _hasSearched = false;
    _sort = SortOption.recommended;
    _filters = const FilterOptions();
    notifyListeners();
  }
}
