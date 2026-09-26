import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'environment.dart';

/// Root Riverpod providers for configuration. This is the only place the app
/// reads build-time configuration; everything else depends on these.
final environmentProvider = Provider<Environment>(
  (ref) => Environment.fromEnvironment,
  name: 'localiq.environment',
);

/// True when repositories should hit the backend rather than the bundled
/// dataset. Flipping this switches data sources without touching UI code.
final remoteDataEnabledProvider = Provider<bool>((ref) {
  final env = ref.watch(environmentProvider);
  return env.hasBackend && !env.useOfflineData;
}, name: 'localiq.remoteDataEnabled');
