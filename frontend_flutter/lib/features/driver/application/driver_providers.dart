import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/providers.dart';
import '../data/local_driver_repository.dart';
import '../data/remote_driver_repository.dart';
import '../domain/driver_repository.dart';
import '../domain/driver_trip.dart';

final driverRepositoryProvider = Provider<DriverRepository>((ref) {
  return ref.watch(remoteDataEnabledProvider)
      ? RemoteDriverRepository(ref.watch(apiClientProvider))
      : LocalDriverRepository();
}, name: 'localiq.driverRepository');

/// The driver's active trips.
final driverTripsProvider = FutureProvider<List<DriverTripSummary>>((ref) async {
  return ref.watch(driverRepositoryProvider).trips();
}, name: 'localiq.driverTrips');

/// One trip, with pickup/stops/drop and route geometry.
final driverTripProvider =
    FutureProvider.family<DriverTrip, int>((ref, id) async {
  return ref.watch(driverRepositoryProvider).trip(id);
}, name: 'localiq.driverTrip');
