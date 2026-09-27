import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/providers.dart';
import '../../context/application/discovery_context_controller.dart';
import '../data/twin_repository.dart';
import '../domain/twin_state.dart';

/// The what-if knobs the user moves. Everything downstream re-derives from this.
class TwinScenario {
  const TwinScenario({
    this.rainLevel = RainLevel.heavy,
    this.durationHours = 2,
    this.floodMultiplier = 1,
    this.active = false,
  });

  final RainLevel rainLevel;
  final double durationHours;
  final double floodMultiplier;

  /// False until the user moves a slider. While false the twin mirrors the
  /// *live* weather, so the demo opens on the real-world baseline.
  final bool active;

  TwinScenario copyWith({
    RainLevel? rainLevel,
    double? durationHours,
    double? floodMultiplier,
    bool? active,
  }) {
    return TwinScenario(
      rainLevel: rainLevel ?? this.rainLevel,
      durationHours: durationHours ?? this.durationHours,
      floodMultiplier: floodMultiplier ?? this.floodMultiplier,
      active: active ?? this.active,
    );
  }
}

class TwinScenarioController extends Notifier<TwinScenario> {
  @override
  TwinScenario build() => const TwinScenario();

  void setRain(RainLevel level) =>
      state = state.copyWith(rainLevel: level, active: true);
  void setDuration(double hours) =>
      state = state.copyWith(durationHours: hours, active: true);
  void setFlood(double multiplier) =>
      state = state.copyWith(floodMultiplier: multiplier, active: true);
  void reset() => state = const TwinScenario();
}

final twinScenarioProvider =
    NotifierProvider<TwinScenarioController, TwinScenario>(
  TwinScenarioController.new,
  name: 'localiq.twinScenario',
);

final twinRepositoryProvider = Provider<TwinRepository>((ref) {
  return ref.watch(remoteDataEnabledProvider)
      ? RemoteTwinRepository(ref.watch(apiClientProvider))
      : LocalTwinRepository(places: ref.watch(placeRepositoryProvider));
}, name: 'localiq.twinRepository');

/// The twin state: live weather until the user simulates, then the scenario.
final twinStateProvider = FutureProvider<TwinState>((ref) async {
  final scenario = ref.watch(twinScenarioProvider);
  final centre = ref.watch(discoveryContextProvider).centre;
  final repo = ref.watch(twinRepositoryProvider);
  if (!scenario.active) {
    return repo.state(centre: centre);
  }
  return repo.simulate(
    centre: centre,
    rainLevel: scenario.rainLevel,
    durationHours: scenario.durationHours,
    floodMultiplier: scenario.floodMultiplier,
  );
}, name: 'localiq.twinState');

/// The twin as it is right now, driven by the live weather.
final liveTwinStateProvider = FutureProvider<TwinState>((ref) async {
  final centre = ref.watch(discoveryContextProvider).centre;
  final repo = ref.watch(twinRepositoryProvider);
  return repo.state(centre: centre);
}, name: 'localiq.liveTwinState');
