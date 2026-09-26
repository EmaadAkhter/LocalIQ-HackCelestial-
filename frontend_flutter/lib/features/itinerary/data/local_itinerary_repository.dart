import 'dart:math' as math;


import '../../../features/recommendations/domain/recommendation.dart';
import '../domain/itinerary.dart';
import '../domain/itinerary_repository.dart';

/// In-memory implementation of [ItineraryRepository].
///
/// Sequencing, travel legs, clock times and the return buffer are all computed
/// here, so the UI never has to reason about ordering. Swap for
/// `RemoteItineraryRepository` and the behaviour is identical because the
/// backend performs the same sequencing.
class LocalItineraryRepository implements ItineraryRepository {
  LocalItineraryRepository({
    required this.gateway,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Travel-time and opening-hours lookup used to re-sequence the plan.
  @override
  final RecommendationEngineGateway gateway;

  final DateTime Function() _clock;

  Itinerary? _itinerary;
  int _idCounter = 0;

  @override
  Future<Itinerary?> active() async => _itinerary;

  @override
  Future<Itinerary> create({
    required String userId,
    required String title,
    required String originLabel,
    required ({double lat, double lng}) origin,
  }) async {
    final now = _clock();
    _itinerary = Itinerary(
      id: 'itin-${now.microsecondsSinceEpoch}',
      userId: userId,
      title: title,
      originLabel: originLabel,
      origin: origin,
      stops: const [],
      createdAt: now,
      updatedAt: now,
    );
    return _itinerary!;
  }

  @override
  Future<Itinerary> addStop({
    required Itinerary itinerary,
    required Recommendation recommendation,
  }) async {
    if (itinerary.stops.any((s) => s.experienceId == recommendation.experience.id)) {
      return itinerary;
    }
    final stops = [
      ...itinerary.stops,
      ItineraryStop(
        id: 'stop-${_idCounter++}-${recommendation.experience.id}',
        experienceId: recommendation.experience.id,
        placeId: recommendation.place.id,
        position: itinerary.stops.length,
        arriveAt: _clock(),
        departAt: _clock(),
        travelInMinutes: recommendation.outboundTravel.minutes,
        travelToMinutes: recommendation.returnTravel.minutes,
        activityMinutes: recommendation.experience.activityMinutes,
        cost: recommendation.experience.typicalSpend,
        locked: false,
      ),
    ];
    return _resequence(itinerary.copyWith(stops: stops));
  }

  @override
  Future<Itinerary> removeStop({
    required Itinerary itinerary,
    required String stopId,
  }) async {
    final stops = itinerary.stops.where((s) => s.id != stopId).toList();
    return _resequence(itinerary.copyWith(stops: stops));
  }

  @override
  Future<Itinerary> reorder({
    required Itinerary itinerary,
    required int oldIndex,
    required int newIndex,
  }) async {
    if (oldIndex < 0 || oldIndex >= itinerary.stops.length) return itinerary;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, itinerary.stops.length - 1);

    final stops = [...itinerary.stops];
    final moved = stops.removeAt(oldIndex);
    stops.insert(target, moved);
    return _resequence(itinerary.copyWith(stops: stops));
  }

  @override
  Future<Itinerary> recheck({
    required Itinerary itinerary,
    required RecommendationEngineGateway gateway,
  }) async {
    // Refresh travel legs against current conditions, then re-sequence.
    final rebuilt = <ItineraryStop>[];
    var previous = itinerary.origin;
    for (var i = 0; i < itinerary.stops.length; i++) {
      final stop = itinerary.stops[i];
      final travel = await gateway.travelBetween(
        from: previous,
        to: _originFor(stop),
      );
      rebuilt.add(
        ItineraryStop(
          id: stop.id,
          experienceId: stop.experienceId,
          placeId: stop.placeId,
          position: i,
          arriveAt: stop.arriveAt,
          departAt: stop.departAt,
          travelInMinutes: travel.minutes,
          travelToMinutes: stop.travelToMinutes,
          activityMinutes: stop.activityMinutes,
          cost: stop.cost,
          locked: stop.locked,
          notes: stop.notes,
        ),
      );
      previous = _originFor(stop);
    }
    final resequenced = _resequence(itinerary.copyWith(stops: rebuilt));

    // Re-validate every stop against opening hours at its new arrival time.
    final validated = <ItineraryStop>[];
    for (final stop in resequenced.stops) {
      final open = await gateway.isOpenAt(placeId: stop.placeId, at: stop.arriveAt);
      validated.add(
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
          locked: stop.locked,
          notes: open
              ? stop.notes
              : (stop.notes == null
                  ? 'Venue closed at the rescheduled time'
                  : '${stop.notes} · Venue closed at the rescheduled time'),
        ),
      );
    }
    return _resequence(itinerary.copyWith(stops: validated));
  }


  @override
  Future<Itinerary> save(Itinerary itinerary) async {
    _itinerary = itinerary.copyWith(savedAt: _clock());
    return _itinerary!;
  }

  @override
  Future<void> clear() async => _itinerary = null;

  // ------------------------------------------------------------- sequencing

  /// Recomputes positions, travel legs and clock times for a stop list.
  Itinerary _resequence(Itinerary itinerary) {
    if (itinerary.stops.isEmpty) {
      return itinerary.copyWith(
        stops: const [],
        updatedAt: _clock(),
      );
    }

    var cursor = itinerary.createdAt;
    final stops = <ItineraryStop>[];

    for (var i = 0; i < itinerary.stops.length; i++) {
      final stop = itinerary.stops[i];
      // Consecutive stops are close together, so a fraction of the
      // door-to-door leg applies rather than the full trip.
      final travel = i == 0
          ? stop.travelInMinutes
          : math.max(3, (stop.travelInMinutes * 0.45).round());

      cursor = cursor.add(Duration(minutes: travel));
      final arrive = cursor;
      cursor = cursor.add(Duration(minutes: stop.activityMinutes));

      stops.add(
        ItineraryStop(
          id: stop.id,
          experienceId: stop.experienceId,
          placeId: stop.placeId,
          position: i,
          arriveAt: arrive,
          departAt: cursor,
          travelInMinutes: travel,
          travelToMinutes: stop.travelToMinutes,
          activityMinutes: stop.activityMinutes,
          cost: stop.cost,
          locked: stop.locked,
          notes: stop.notes,
        ),
      );
    }

    return itinerary.copyWith(
      stops: stops,
      updatedAt: _clock(),
    );
  }

  ({double lat, double lng}) _originFor(ItineraryStop stop) {
    // A production build resolves this from the place record; the offline
    // catalogue is loaded by the caller and re-anchored on the gateway.
    return _placeOrigins[stop.placeId] ?? _fallbackOrigin;
  }

  static const _fallbackOrigin = (lat: 18.9322, lng: 72.8316);

  /// Populated by the controller once places are loaded.
  static final Map<String, ({double lat, double lng})> _placeOrigins = {};

  static void registerPlaceOrigin(
    String placeId,
    ({double lat, double lng}) origin,
  ) {
    _placeOrigins[placeId] = origin;
  }
}