import 'dart:math' as math;

import '../domain/driver_repository.dart';
import '../domain/driver_trip.dart';

/// Offline [DriverRepository]. Returns one demo trip through the same interface
/// the remote one implements, so the driver map is fully explorable without a
/// backend (and in tests).
class LocalDriverRepository implements DriverRepository {
  LocalDriverRepository();

  static const _pickup = (lat: 19.0596, lng: 72.8295); // Bandra
  static const _stopA = (lat: 18.9647, lng: 72.8258); // Dadar flower market
  static const _stopB = (lat: 18.9398, lng: 72.8355); // Fort / CSMT
  static const _stopC = (lat: 18.9220, lng: 72.8317); // Kala Ghoda
  static const _drop = (lat: 18.9067, lng: 72.8147); // Colaba Causeway

  DriverTrip _trip = _initial();

  static DriverTrip _initial() => DriverTrip(
        id: 1,
        bookingRef: 'LOCAL-1',
        status: 'confirmed',
        guideId: 1,
        allowedTransitions: const ['in_progress', 'cancelled'],
        date: _today(),
        startTime: '10:00',
        hours: 3,
        groupSize: 2,
        guestName: 'Demo Guest',
        guestPhone: '+91 90000 00000',
        note: 'Guest is staying near Bandra station.',
        packageTitle: 'South Mumbai Heritage Walk',
        guideName: 'Your LocalIQ guide',
        pickup: TripPoint(
          lat: _pickup.lat,
          lng: _pickup.lng,
          label: 'Pickup',
          address: 'Bandra Station (West), Mumbai',
        ),
        drop: TripPoint(
          lat: _drop.lat,
          lng: _drop.lng,
          label: 'Drop-off',
          address: 'Colaba Causeway, Mumbai',
        ),
        stops: [
          TripStop(sequence: 1, name: 'Dadar Flower Market', lat: _stopA.lat, lng: _stopA.lng, durationMin: 40),
          TripStop(sequence: 2, name: 'CSMT & Fort Walk', lat: _stopB.lat, lng: _stopB.lng, durationMin: 60),
          TripStop(sequence: 3, name: 'Kala Ghoda Art District', lat: _stopC.lat, lng: _stopC.lng, durationMin: 45),
        ],
        route: _route(const [
          _pickup,
          _stopA,
          _stopB,
          _stopC,
          _drop,
        ]),
        distanceKm: 21.4,
        durationMin: 52,
        routeSource: 'local',
      );

  static String _today() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  /// Mirror of the backend's road-like curve so the offline map has a route.
  static List<({double lat, double lng})> _route(
    List<({double lat, double lng})> points, {
    int perLeg = 12,
  }) {
    final path = <({double lat, double lng})>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (i == 0) path.add(a);
      final dLat = b.lat - a.lat;
      final dLng = b.lng - a.lng;
      final span = math.sqrt(dLat * dLat + dLng * dLng);
      if (span == 0) continue;
      final perpLat = -dLng / span;
      final perpLng = dLat / span;
      const bow = 0.0005;
      for (var step = 1; step <= perLeg; step++) {
        final t = step / perLeg;
        final curve = math.sin(math.pi * t) * bow;
        path.add((
          lat: a.lat + dLat * t + perpLat * curve,
          lng: a.lng + dLng * t + perpLng * curve,
        ));
      }
    }
    return path;
  }

  static const _transitions = {
    'requested': ['confirmed', 'cancelled'],
    'pending': ['confirmed', 'cancelled'],
    'confirmed': ['in_progress', 'cancelled'],
    'in_progress': ['completed'],
    'completed': <String>[],
    'cancelled': <String>[],
  };

  @override
  Future<List<DriverTripSummary>> trips({bool includeCompleted = false}) async {
    if (_trip.isCompleted && !includeCompleted) return const [];
    return [
      DriverTripSummary(
        id: _trip.id,
        bookingRef: _trip.bookingRef,
        status: _trip.status,
        date: _trip.date,
        startTime: _trip.startTime,
        groupSize: _trip.groupSize,
        guestName: _trip.guestName,
        packageTitle: _trip.packageTitle,
        pickupAddress: _trip.pickup?.address,
        pickup: _trip.pickup,
        hasDriverLocation: _trip.driverLocation != null,
      ),
    ];
  }

  @override
  Future<DriverTrip> trip(int id) async => _trip;

  @override
  Future<DriverTrip> setStatus(int id, String status) async {
    if (!_trip.allowedTransitions.contains(status)) {
      throw StateError("cannot go from '${_trip.status}' to '$status'");
    }
    _trip = _copy(status: status, allowedTransitions: _transitions[status] ?? const []);
    return _trip;
  }

  @override
  Future<DriverTrip> reportLocation(
    int id, {
    required double lat,
    required double lng,
  }) async {
    final drop = _trip.drop;
    TripRemaining? remaining;
    if (drop != null) {
      final km = _haversine(lat, lng, drop.lat, drop.lng);
      remaining = TripRemaining(
        distanceKm: double.parse(km.toStringAsFixed(2)),
        durationMin: math.max(1, (km / 22 * 60).round()),
      );
    }
    _trip = _copy(
      driverLocation: TripPoint(lat: lat, lng: lng, label: 'Driver'),
      remaining: remaining,
    );
    return _trip;
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const radius = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  DriverTrip _copy({
    String? status,
    List<String>? allowedTransitions,
    TripPoint? driverLocation,
    TripRemaining? remaining,
  }) {
    return DriverTrip(
      id: _trip.id,
      bookingRef: _trip.bookingRef,
      status: status ?? _trip.status,
      guideId: _trip.guideId,
      allowedTransitions: allowedTransitions ?? _trip.allowedTransitions,
      date: _trip.date,
      startTime: _trip.startTime,
      hours: _trip.hours,
      groupSize: _trip.groupSize,
      guestName: _trip.guestName,
      guestPhone: _trip.guestPhone,
      note: _trip.note,
      packageTitle: _trip.packageTitle,
      guideName: _trip.guideName,
      pickup: _trip.pickup,
      drop: _trip.drop,
      stops: _trip.stops,
      route: _trip.route,
      distanceKm: _trip.distanceKm,
      durationMin: _trip.durationMin,
      routeSource: _trip.routeSource,
      driverLocation: driverLocation ?? _trip.driverLocation,
      remaining: remaining ?? _trip.remaining,
    );
  }
}
