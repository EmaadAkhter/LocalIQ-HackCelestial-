import 'driver_trip.dart';

/// Driver trip access. `RemoteDriverRepository` talks to the backend;
/// `LocalDriverRepository` provides a demo trip so the map is explorable
/// offline through the same interface.
abstract interface class DriverRepository {
  Future<List<DriverTripSummary>> trips({bool includeCompleted = false});

  Future<DriverTrip> trip(int id);

  Future<DriverTrip> setStatus(int id, String status);

  Future<DriverTrip> reportLocation(int id, {required double lat, required double lng});
}
