import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/travel_buddy_service.dart';

final travelBuddyServiceProvider = Provider<TravelBuddyService>(
  (ref) => TravelBuddyService(ref.watch(apiClientProvider)),
  name: 'localiq.travelBuddyService',
);
