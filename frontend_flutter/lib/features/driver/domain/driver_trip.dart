import '../../../core/utils/json_map_x.dart';

/// A coordinate with an optional human label/address (pickup, drop-off...).
class TripPoint {
  const TripPoint({
    required this.lat,
    required this.lng,
    this.label,
    this.address,
  });

  final double lat;
  final double lng;
  final String? label;
  final String? address;

  ({double lat, double lng}) get position => (lat: lat, lng: lng);

  String get title => label ?? address ?? 'Point';

  factory TripPoint.fromJson(Map<String, dynamic> json) => TripPoint(
        lat: json.doubleValue('lat'),
        lng: json.doubleValue('lng'),
        label: json.stringOrNull('label'),
        address: json.stringOrNull('address'),
      );
}

/// One ordered stop on the route.
class TripStop {
  const TripStop({
    required this.sequence,
    this.name,
    this.lat,
    this.lng,
    this.durationMin = 0,
    this.travelTimeMin = 0,
    this.segmentType = 'experience',
    this.guideNotes,
  });

  final int sequence;
  final String? name;
  final double? lat;
  final double? lng;
  final int durationMin;
  final int travelTimeMin;
  final String segmentType;
  final String? guideNotes;

  ({double lat, double lng})? get position =>
      (lat != null && lng != null) ? (lat: lat!, lng: lng!) : null;

  factory TripStop.fromJson(Map<String, dynamic> json) => TripStop(
        sequence: json.intValue('sequence'),
        name: json.stringOrNull('name'),
        lat: json.doubleOrNull('lat'),
        lng: json.doubleOrNull('lng'),
        durationMin: json.intValue('durationMin'),
        travelTimeMin: json.intValue('travelTimeMin'),
        segmentType: json.string('segmentType') ?? 'experience',
        guideNotes: json.stringOrNull('guideNotes'),
      );
}

class TripRemaining {
  const TripRemaining({required this.distanceKm, required this.durationMin});

  final double distanceKm;
  final int durationMin;

  String get label => '${durationMin} min · ${distanceKm.toStringAsFixed(1)} km left';

  factory TripRemaining.fromJson(Map<String, dynamic> json) => TripRemaining(
        distanceKm: json.doubleValue('distanceKm'),
        durationMin: json.intValue('durationMin'),
      );
}

/// A trip row in the driver's list.
class DriverTripSummary {
  const DriverTripSummary({
    required this.id,
    required this.bookingRef,
    required this.status,
    this.date,
    this.startTime,
    this.groupSize = 1,
    this.guestName,
    this.packageTitle,
    this.pickupAddress,
    this.pickup,
    this.hasDriverLocation = false,
  });

  final int id;
  final String bookingRef;
  final String status;
  final String? date;
  final String? startTime;
  final int groupSize;
  final String? guestName;
  final String? packageTitle;
  final String? pickupAddress;
  final TripPoint? pickup;
  final bool hasDriverLocation;

  String get title => packageTitle ?? 'Trip $bookingRef';

  String get whenLabel {
    if (date == null) return '';
    final time = (startTime ?? '').isNotEmpty ? ' · $startTime' : '';
    return '$date$time';
  }

  factory DriverTripSummary.fromJson(Map<String, dynamic> json) {
    final pickup = json.pick('pickup');
    return DriverTripSummary(
      id: json.intValue('id'),
      bookingRef: json.string('bookingRef') ?? '',
      status: json.string('status') ?? 'pending',
      date: json.stringOrNull('date'),
      startTime: json.stringOrNull('startTime'),
      groupSize: json.intValue('groupSize', fallback: 1),
      guestName: json.stringOrNull('guestName'),
      packageTitle: json.stringOrNull('packageTitle'),
      pickupAddress: json.stringOrNull('pickupAddress'),
      pickup: pickup is Map
          ? TripPoint.fromJson(pickup.cast<String, dynamic>())
          : null,
      hasDriverLocation: json.boolValue('hasDriverLocation'),
    );
  }
}

/// The full trip the driver map renders.
class DriverTrip {
  const DriverTrip({
    required this.id,
    required this.bookingRef,
    required this.status,
    required this.guideId,
    this.allowedTransitions = const [],
    this.date,
    this.startTime,
    this.hours = 2,
    this.groupSize = 1,
    this.guestName,
    this.guestPhone,
    this.note,
    this.packageTitle,
    this.guideName,
    this.pickup,
    this.drop,
    this.stops = const [],
    this.route = const [],
    this.distanceKm = 0,
    this.durationMin = 0,
    this.routeSource = 'local',
    this.driverLocation,
    this.remaining,
  });

  final int id;
  final String bookingRef;
  final String status;
  final int guideId;
  final List<String> allowedTransitions;
  final String? date;
  final String? startTime;
  final int hours;
  final int groupSize;
  final String? guestName;
  final String? guestPhone;
  final String? note;
  final String? packageTitle;
  final String? guideName;
  final TripPoint? pickup;
  final TripPoint? drop;
  final List<TripStop> stops;
  final List<({double lat, double lng})> route;
  final double distanceKm;
  final int durationMin;
  final String routeSource;
  final TripPoint? driverLocation;
  final TripRemaining? remaining;

  String get title => packageTitle ?? 'Trip $bookingRef';

  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';

  String get statusLabel => switch (status) {
        'requested' || 'pending' => 'Requested',
        'accepted' => 'Accepted',
        'confirmed' => 'Confirmed',
        'in_progress' => 'On trip',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        _ => status,
      };

  bool can(String target) => allowedTransitions.contains(target);

  /// The next action the driver is most likely to take.
  String? get primaryAction {
    if (can('in_progress')) return 'in_progress';
    if (can('completed')) return 'completed';
    if (can('confirmed')) return 'confirmed';
    return null;
  }

  String get primaryActionLabel => switch (primaryAction) {
        'confirmed' => 'Accept trip',
        'in_progress' => 'Start trip',
        'completed' => 'Complete trip',
        _ => 'Update',
      };

  factory DriverTrip.fromJson(Map<String, dynamic> json) {
    TripPoint? point(String key) {
      final value = json.pick(key);
      return value is Map ? TripPoint.fromJson(value.cast<String, dynamic>()) : null;
    }

    final remaining = json.pick('remaining');
    return DriverTrip(
      id: json.intValue('id'),
      bookingRef: json.string('bookingRef') ?? '',
      status: json.string('status') ?? 'pending',
      guideId: json.intValue('guideId'),
      allowedTransitions: json.stringList('allowedTransitions'),
      date: json.stringOrNull('date'),
      startTime: json.stringOrNull('startTime'),
      hours: json.intValue('hours', fallback: 2),
      groupSize: json.intValue('groupSize', fallback: 1),
      guestName: json.stringOrNull('guestName'),
      guestPhone: json.stringOrNull('guestPhone'),
      note: json.stringOrNull('note'),
      packageTitle: json.stringOrNull('packageTitle'),
      guideName: json.stringOrNull('guideName'),
      pickup: point('pickup'),
      drop: point('drop'),
      stops: json
          .mapList('stops')
          .map(TripStop.fromJson)
          .toList(growable: false),
      route: json
          .mapList('route')
          .map((m) => (lat: m.doubleValue('lat'), lng: m.doubleValue('lng')))
          .toList(growable: false),
      distanceKm: json.doubleValue('distanceKm'),
      durationMin: json.intValue('durationMin'),
      routeSource: json.string('routeSource') ?? 'local',
      driverLocation: point('driverLocation'),
      remaining: remaining is Map
          ? TripRemaining.fromJson(remaining.cast<String, dynamic>())
          : null,
    );
  }
}
