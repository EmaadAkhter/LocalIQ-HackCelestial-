import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/google_sign_in_service.dart';
import '../features/auth/data/local_auth_service.dart';
import '../features/auth/data/remote_auth_service.dart';
import '../features/auth/domain/auth_service.dart';
import '../features/context/data/local_context_repository.dart';
import '../features/context/data/remote_context_repository.dart';
import '../features/itinerary/data/local_itinerary_repository.dart';
import '../features/itinerary/domain/itinerary_repository.dart';
import '../features/places/data/local_place_repository.dart';
import '../features/places/data/remote_place_repository.dart';
import '../features/places/domain/place.dart';
import '../features/places/domain/place_repository.dart';
import '../features/recommendations/data/feasibility_engine.dart';
import '../features/recommendations/domain/recommendation_engine.dart';
import '../features/routing/application/routing_providers.dart';
import '../features/routing/data/google_routes_service.dart';
import '../features/routing/data/local_routes_service.dart';
import '../features/routing/domain/routes_service.dart';
import '../features/saved/data/saved_repository.dart';
import '../features/assistant/data/contextual_assistant_service.dart';
import '../features/assistant/domain/assistant_service.dart';
import 'config/providers.dart';
import 'network/auth_token_holder.dart';
import 'network/json_api_client.dart';

/// ---------------------------------------------------------------------------
/// Data sources
///
/// Every provider below is an interface. Which implementation is bound is a
/// single switch on [remoteDataEnabledProvider], so pointing the app at a
/// backend never requires a UI change.
/// ---------------------------------------------------------------------------

final apiClientProvider = Provider<JsonApiClient>((ref) {
  final env = ref.watch(environmentProvider);
  final tokenHolder = ref.watch(authTokenHolderProvider);
  final client = JsonApiClient(
    baseUrl: env.apiBaseUrl,
    timeout: env.requestTimeout,
    apiKey: env.apiKey,
    tokenProvider: () => tokenHolder.accessToken,
  );
  ref.onDispose(client.dispose);
  return client;
}, name: 'localiq.apiClient');

/// Carries the signed-in user's access token to [JsonApiClient]. Owned here so
/// the client (built early) and the auth service (built later) never form a
/// dependency cycle.
final authTokenHolderProvider = Provider<AuthTokenHolder>(
  (ref) => AuthTokenHolder(),
  name: 'localiq.authTokenHolder',
);

// ------------------------------------------------------------------- places

final placeRepositoryProvider = Provider<PlaceRepository>((ref) {
  return ref.watch(remoteDataEnabledProvider)
      ? RemotePlaceRepository(ref.watch(apiClientProvider))
      : LocalPlaceRepository();
}, name: 'localiq.placeRepository');

/// The full catalogue, hydrated once. Small enough to hold in memory and the
/// basis for local search and the recommendation engine.
///
/// This is a catalogue load, not a proximity search: `near` is deliberately
/// omitted (the server then returns every place, unranked by distance) and
/// `limit: 0` asks for the lot. Distances are computed client-side from each
/// place's centre, so no user radius is involved — and none is invented here.
final allPlacesProvider = FutureProvider<List<Place>>((ref) async {
  final repo = ref.watch(placeRepositoryProvider);
  return repo.search(const PlaceQuery(limit: 0));
}, name: 'localiq.allPlaces');

final allExperiencesProvider = FutureProvider<List<Experience>>((ref) async {
  final repo = ref.watch(placeRepositoryProvider);
  final places = await ref.watch(allPlacesProvider.future);
  final all = <Experience>[];
  for (final place in places) {
    all.addAll(await repo.experiencesForPlace(place.id));
  }
  return all;
}, name: 'localiq.allExperiences');

/// Home rail: "Recommended for you", taste-ranked by the backend.
final forYouPlacesProvider = FutureProvider<List<Place>>((ref) async {
  final repo = ref.watch(placeRepositoryProvider);
  return repo.forYou(limit: 12);
}, name: 'localiq.forYouPlaces');

/// Home rail: "Perfect right now", ranked by the live moment (weather, time,
/// crowd). Each place carries a `rightNowLabel` the card renders as a badge.
final rightNowPlacesProvider = FutureProvider<List<Place>>((ref) async {
  final repo = ref.watch(placeRepositoryProvider);
  return repo.rightNow(limit: 12);
}, name: 'localiq.rightNowPlaces');

/// Home rail: "Hidden gems", only genuine local finds (backend applies a floor).
final gemPlacesProvider = FutureProvider<List<Place>>((ref) async {
  final repo = ref.watch(placeRepositoryProvider);
  return repo.localGems(limit: 12);
}, name: 'localiq.gemPlaces');

final placeByIdProvider = Provider.family<Place?, String>((ref, id) {
  final places = ref.watch(allPlacesProvider).value ?? const <Place>[];
  for (final place in places) {
    if (place.id == id) return place;
  }
  return null;
}, name: 'localiq.placeById');

/// Fetches a single place by id from the repository. Use this for the detail
/// screen when the place may not already be in the in-memory catalogue.
final placeDetailProvider = FutureProvider.family<Place?, String>((ref, id) async {
  final repo = ref.watch(placeRepositoryProvider);
  return repo.placeById(id);
}, name: 'localiq.placeDetail');

/// Free-text place lookup backed by Google Places (`/places/search`).
///
/// Keyed by the query string; callers should debounce before flipping the key
/// so every keystroke does not become a Google round-trip.
final placeSearchProvider =
    FutureProvider.family<List<Place>, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const <Place>[];
  final repo = ref.watch(placeRepositoryProvider);
  return repo.searchRemote(trimmed);
}, name: 'localiq.placeSearch');

final experienceByIdProvider =
    Provider.family<Experience?, String>((ref, id) {
  final list =
      ref.watch(allExperiencesProvider).value ?? const <Experience>[];
  for (final experience in list) {
    if (experience.id == id) return experience;
  }
  return null;
}, name: 'localiq.experienceById');

// ------------------------------------------------------------------ context

final contextRepositoryProvider = Provider<ContextRepository>((ref) {
  return ref.watch(remoteDataEnabledProvider)
      ? RemoteContextRepository(ref.watch(apiClientProvider))
      : LocalContextRepository();
}, name: 'localiq.contextRepository');

// -------------------------------------------------------------------- auth

final authServiceProvider = Provider<AuthService>((ref) {
  if (!ref.watch(remoteDataEnabledProvider)) return LocalAuthService();
  return RemoteAuthService(
    ref.watch(apiClientProvider),
    tokenHolder: ref.watch(authTokenHolderProvider),
  );
}, name: 'localiq.authService');

/// Google Sign-In: obtains the idToken that `signInWithGoogle` requires.
/// Kept separate from the auth service so a build with no client id still works
/// (the button reports a clear message instead of failing at construction).
final googleSignInServiceProvider = Provider<GoogleSignInService>((ref) {
  return GoogleSignInService();
}, name: 'localiq.googleSignIn');

/// Current session, seeded from the auth service and updated on every change.
final authSessionProvider = StreamProvider<AuthSession?>((ref) {
  final service = ref.watch(authServiceProvider);
  return service.authStateChanges();
}, name: 'localiq.authSession');

final currentUserProvider = Provider<LocalIqUser?>((ref) {
  return ref.watch(authServiceProvider).currentUser;
}, name: 'localiq.currentUser');

// --------------------------------------------------------- recommendations

final recommendationEngineProvider = Provider<RecommendationEngine>((ref) {
  return FeasibilityEngine();
}, name: 'localiq.recommendationEngine');

// ----------------------------------------------------------------- routing

final routesServiceProvider = Provider<RoutesService>((ref) {
  final env = ref.watch(environmentProvider);
  if (env.hasGoogleMaps) {
    return GoogleRoutesService(
      apiKey: env.mapsKey!,
      client: ref.watch(apiClientProvider),
    );
  }
  return const LocalRoutesService();
}, name: 'localiq.routesService');

/// Map surface provider. Reports whether real tiles are available so the UI
/// can render the vector fallback without a second code path in the widgets.
final mapServiceProvider = Provider<MapService>((ref) {
  final env = ref.watch(environmentProvider);
  return GoogleMapService(hasTiles: env.hasGoogleMaps, apiKey: env.mapsKey);
}, name: 'localiq.mapService');

// --------------------------------------------------------------- assistant

final assistantServiceProvider = Provider<AssistantService>((ref) {
  return const ContextualAssistantService();
}, name: 'localiq.assistantService');

// --------------------------------------------------------------- itinerary

final itineraryRepositoryProvider = Provider<ItineraryRepository>((ref) {
  return LocalItineraryRepository(
    gateway: LocalItineraryGateway(
      routes: ref.watch(routesServiceProvider),
      places: ref.watch(placeRepositoryProvider),
    ),
  );
}, name: 'localiq.itineraryRepository');

// ------------------------------------------------------------------ saved

final savedRepositoryProvider = Provider<SavedRepository>((ref) {
  return LocalSavedRepository();
}, name: 'localiq.savedRepository');
