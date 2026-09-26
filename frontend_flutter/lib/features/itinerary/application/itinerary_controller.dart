import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../context/application/discovery_context_controller.dart';
import '../../places/domain/place.dart';
import '../../recommendations/domain/recommendation.dart';
import '../domain/itinerary.dart';

/// Owns the active plan. All sequencing and timing is delegated to the
/// repository, so this controller only expresses intent.
class ItineraryController extends AsyncNotifier<Itinerary?> {
  @override
  Future<Itinerary?> build() async {
    final repo = ref.watch(itineraryRepositoryProvider);
    final existing = await repo.active();
    if (existing != null) return existing;
    final discovery = ref.watch(discoveryContextProvider);
    return repo.create(
      userId: 'local',
      title: 'Today in ${discovery.locationLabel}',
      originLabel: discovery.locationLabel,
      origin: discovery.pin,
    );
  }

  Future<void> add(Recommendation recommendation) async {
    final repo = ref.watch(itineraryRepositoryProvider);
    final current = state.value ?? await build();
    if (current == null) return;
    if (current.stops
        .any((s) => s.experienceId == recommendation.experience.id)) {
      return;
    }
    _registerOrigin(recommendation.place);
    state = AsyncData(
      await repo.addStop(itinerary: current, recommendation: recommendation),
    );
  }

  Future<void> remove(String stopId) async {
    final repo = ref.watch(itineraryRepositoryProvider);
    final current = state.value;
    if (current == null) return;
    state = AsyncData(await repo.removeStop(itinerary: current, stopId: stopId));
  }

  Future<void> move(int oldIndex, int newIndex) async {
    final repo = ref.watch(itineraryRepositoryProvider);
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      await repo.reorder(
        itinerary: current,
        oldIndex: oldIndex,
        newIndex: newIndex,
      ),
    );
  }

  Future<void> toggleLock(String stopId) async {
    final current = state.value;
    if (current == null) return;
    final stops = [
      for (final stop in current.stops)
        if (stop.id == stopId)
          ItineraryStop(
            id: stop.id,
            experienceId: stop.experienceId,
            placeId: stop.placeId,
            position: stop.position,
            arriveAt: stop.arriveAt,
            departAt: stop.departAt,
            travelInMinutes: stop.travelInMinutes,
            travelToMinutes: stop.travelToMinutes,
            activityMinutes: stop.activityMinutes,
            cost: stop.cost,
            locked: !stop.locked,
            notes: stop.notes,
          )
        else
          stop,
    ];
    state = AsyncData(current.copyWith(stops: stops, updatedAt: DateTime.now()));
  }

  Future<void> recheck() async {
    final repo = ref.watch(itineraryRepositoryProvider);
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      await repo.recheck(itinerary: current, gateway: repo.gateway),
    );
  }

  Future<void> save() async {
    final repo = ref.watch(itineraryRepositoryProvider);
    final current = state.value;
    if (current == null) return;
    state = AsyncData(await repo.save(current));
  }

  Future<void> clear() async {
    final repo = ref.watch(itineraryRepositoryProvider);
    await repo.clear();
    state = const AsyncData(null);
  }

  void _registerOrigin(Place place) {
    // The offline gateway resolves coordinates from this registry.
    LocalItineraryOriginRegistry.register(place.id, place.pin);
  }
}

/// Small indirection so the controller does not import the concrete repository.
abstract final class LocalItineraryOriginRegistry {
  static final _registry = <String, ({double lat, double lng})>{};
  static final _writers = <void Function(String, ({double lat, double lng}))>[];

  static void register(String placeId, ({double lat, double lng}) origin) {
    _registry[placeId] = origin;
    for (final writer in _writers) {
      writer(placeId, origin);
    }
  }

  static ({double lat, double lng})? lookup(String placeId) =>
      _registry[placeId];

  static void onRegister(
    void Function(String, ({double lat, double lng})) writer,
  ) =>
      _writers.add(writer);
}

final itineraryControllerProvider =
    AsyncNotifierProvider<ItineraryController, Itinerary?>(
  ItineraryController.new,
  name: 'localiq.itinerary',
);

/// Plan verdict for the active window.
final itineraryStatusProvider = Provider<ItineraryStatus>((ref) {
  final itinerary = ref.watch(itineraryControllerProvider).value;
  final context = ref.watch(discoveryContextProvider);
  return itinerary?.statusFor(context.timeBudgetMinutes) ??
      ItineraryStatus.empty;
});

/// A stop joined with its live place + experience for rendering.
class ResolvedStop {
  const ResolvedStop({required this.stop, required this.place, required this.experience});

  final ItineraryStop stop;
  final Place place;
  final Experience experience;

  String get timeLabel => '${_clock(stop.arriveAt)} – ${_clock(stop.departAt)}';

  static String _clock(DateTime time) {
    final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m ${time.hour >= 12 ? 'PM' : 'AM'}';
  }
}

final resolvedStopsProvider = Provider<List<ResolvedStop>>((ref) {
  final itinerary = ref.watch(itineraryControllerProvider).value;
  if (itinerary == null) return const [];
  final places = ref.watch(allPlacesProvider).value ?? const <Place>[];
  final experiences =
      ref.watch(allExperiencesProvider).value ?? const <Experience>[];

  final byPlace = {for (final p in places) p.id: p};
  final byExperience = {for (final e in experiences) e.id: e};

  final out = <ResolvedStop>[];
  for (final stop in itinerary.stops) {
    final place = byPlace[stop.placeId];
    final experience = byExperience[stop.experienceId];
    if (place != null && experience != null) {
      out.add(
        ResolvedStop(stop: stop, place: place, experience: experience),
      );
    }
  }
  return out;
});
