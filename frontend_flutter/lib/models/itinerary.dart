import 'place.dart';

/// One ordered stop in a plan.
class ItineraryStop {
  const ItineraryStop({
    required this.place,
    required this.visitMinutes,
    required this.travelFromPreviousMinutes,
    this.startTimeLabel,
  });

  final Place place;

  /// Time spent at the place.
  final int visitMinutes;

  /// Travel time from the previous stop (0 for the first stop).
  final int travelFromPreviousMinutes;

  /// e.g. "11:00 AM" — computed when the plan is built.
  final String? startTimeLabel;

  ItineraryStop copyWith({String? startTimeLabel}) {
    return ItineraryStop(
      place: place,
      visitMinutes: visitMinutes,
      travelFromPreviousMinutes: travelFromPreviousMinutes,
      startTimeLabel: startTimeLabel ?? this.startTimeLabel,
    );
  }
}

/// An ordered day plan with running totals.
class ItineraryPlan {
  const ItineraryPlan({required this.title, required this.stops, this.savedAt});

  final String title;
  final List<ItineraryStop> stops;
  final DateTime? savedAt;

  bool get isEmpty => stops.isEmpty;
  bool get isSaved => savedAt != null;

  /// Sum of travel legs.
  int get travelMinutes => stops.fold<int>(
    0,
    (int sum, ItineraryStop s) => sum + s.travelFromPreviousMinutes,
  );

  /// Sum of visits.
  int get visitMinutes =>
      stops.fold<int>(0, (int sum, ItineraryStop s) => sum + s.visitMinutes);

  /// Travel + visits.
  int get totalMinutes => travelMinutes + visitMinutes;

  /// Sum of estimated per-person spend.
  int get totalCost =>
      stops.fold<int>(0, (int sum, ItineraryStop s) => sum + s.place.avgCost);

  int get stopCount => stops.length;

  /// Re-label each stop with a start time starting from 10:00 AM.
  ItineraryPlan withStartTimes({int startHour = 10}) {
    var cursor = startHour * 60;
    final List<ItineraryStop> updated = <ItineraryStop>[];
    for (final ItineraryStop stop in stops) {
      if (stop.travelFromPreviousMinutes > 0) {
        cursor += stop.travelFromPreviousMinutes;
      }
      final label = _label(cursor);
      updated.add(stop.copyWith(startTimeLabel: label));
      cursor += stop.visitMinutes;
    }
    return copyWith(stops: updated);
  }

  ItineraryPlan copyWith({List<ItineraryStop>? stops, DateTime? savedAt}) {
    return ItineraryPlan(
      title: title,
      stops: stops ?? this.stops,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  static String _label(int minutesOfDay) {
    final h = (minutesOfDay ~/ 60) % 24;
    final m = minutesOfDay % 60;
    final period = h >= 12 ? 'PM' : 'AM';
    var hour = h % 12;
    if (hour == 0) hour = 12;
    return '$hour:${m.toString().padLeft(2, '0')} $period';
  }
}
