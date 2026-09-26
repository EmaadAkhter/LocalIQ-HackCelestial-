import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../itinerary/application/itinerary_controller.dart';
import '../../itinerary/domain/itinerary.dart';

/// The active itinerary, exposed under a dedicated name so feature widgets can
/// watch it without importing the whole itinerary controller.
final itineraryForPlanProvider = Provider<AsyncValue<Itinerary?>>((ref) {
  return ref.watch(itineraryControllerProvider);
});
