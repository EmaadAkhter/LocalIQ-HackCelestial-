import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../domain/context_models.dart';
import '../domain/discovery_context.dart';

/// The single source of truth for what the user is looking for right now.
///
/// Every recommendation, the map, the plan and the assistant read from this.
/// Changing any input recomputes the live context and the ranking.
class DiscoveryContextController extends Notifier<DiscoveryContext> {
  @override
  DiscoveryContext build() {
    final now = DateTime.now();
    return DiscoveryContext(
      locationLabel: 'Fort, South Mumbai',
      centre: const GeoPoint(latitude: 18.9322, longitude: 72.8316),
      timeBudgetMinutes: 120,
      // Default to "now" rounded to the next quarter hour so opening-hours
      // checks are meaningful from the first frame.
      startTime: DateTime(
        now.year,
        now.month,
        now.day,
        (now.hour + 1).clamp(0, 23),
        0,
      ),
      budget: 1000,
      interests: const {
        ExperienceCategory.food,
        ExperienceCategory.culture,
        ExperienceCategory.history,
        ExperienceCategory.art,
      },
      groupType: GroupType.solo,
      accessibility: AccessibilityNeed.none,
      localBias: 0.3,
      query: '',
    );
  }

  void setTime(int minutes) =>
      state = state.copyWith(timeBudgetMinutes: minutes.clamp(30, 600));

  void setBudget(int amount) => state = state.copyWith(budget: amount.clamp(200, 8000));

  void setWeather(WeatherCondition condition) {
    // Weather is a live condition, not a user preference, so it lives on the
    // context repository. This setter exists for the what-if lab where the
    // user explicitly wants to explore a different condition.
    ref.read(weatherOverrideProvider.notifier).set(condition);
  }

  /// Returns to the live, observed conditions.
  void setWeatherReset() => ref.read(weatherOverrideProvider.notifier).set(null);

  void setGroup(GroupType group) => state = state.copyWith(groupType: group);

  void setAccessibility(AccessibilityNeed need) =>
      state = state.copyWith(accessibility: need);

  void setLocalBias(double bias) => state = state.copyWith(localBias: bias);

  void setQuery(String query) => state = state.copyWith(query: query);

  void setLocation(String label, GeoPoint centre) =>
      state = state.copyWith(locationLabel: label, centre: centre);

  void setStartTime(DateTime time) => state = state.copyWith(startTime: time);

  void toggleInterest(ExperienceCategory category) {
    final next = {...state.interests};
    if (!next.remove(category)) next.add(category);
    state = state.copyWith(interests: next);
  }

  void reset() {
    final now = DateTime.now();
    state = DiscoveryContext(
      locationLabel: 'Fort, South Mumbai',
      centre: const GeoPoint(latitude: 18.9322, longitude: 72.8316),
      timeBudgetMinutes: 120,
      startTime: DateTime(now.year, now.month, now.day, now.hour + 1, 0),
      budget: 1000,
      interests: const {
        ExperienceCategory.food,
        ExperienceCategory.culture,
        ExperienceCategory.history,
        ExperienceCategory.art,
      },
      groupType: GroupType.solo,
      accessibility: AccessibilityNeed.none,
      localBias: 0.3,
      query: '',
    );
    ref.read(weatherOverrideProvider.notifier).set(null);
  }

  /// Applies a one-tap scenario.
  void applyScenario(DiscoveryScenario scenario) {
    state = state.copyWith(
      timeBudgetMinutes: scenario.minutes,
      budget: scenario.budget,
      groupType: scenario.group,
      interests: scenario.interests,
      accessibility: scenario.accessibility,
      localBias: scenario.localBias,
      query: '',
    );
    ref.read(weatherOverrideProvider.notifier).set(scenario.weather);
  }
}

/// Optional weather override, used by the what-if lab to explore how the
/// ranking would change under different conditions. Null means "live".
class WeatherOverrideController extends Notifier<WeatherCondition?> {
  @override
  WeatherCondition? build() => null;

  void set(WeatherCondition? condition) => state = condition;
}

/// Weather override selector, so the UI can show which mode is active.
final weatherOverrideProvider =
    NotifierProvider<WeatherOverrideController, WeatherCondition?>(
  WeatherOverrideController.new,
  name: 'localiq.weatherOverride',
);

/// Quick scenario presets surfaced on Explore.
class DiscoveryScenario {
  const DiscoveryScenario({
    required this.id,
    required this.label,
    required this.caption,
    required this.minutes,
    required this.budget,
    required this.interests,
    required this.group,
    required this.accessibility,
    required this.localBias,
    this.weather,
  });

  final String id;
  final String label;
  final String caption;
  final int minutes;
  final int budget;
  final Set<ExperienceCategory> interests;
  final GroupType group;
  final AccessibilityNeed accessibility;
  final double localBias;
  final WeatherCondition? weather;
}

const discoveryScenarios = <DiscoveryScenario>[
  DiscoveryScenario(
    id: 'now-2h',
    label: 'Two hours, right now',
    caption: 'The default Fort loop',
    minutes: 120,
    budget: 1000,
    interests: {
      ExperienceCategory.food,
      ExperienceCategory.culture,
      ExperienceCategory.art,
    },
    group: GroupType.solo,
    accessibility: AccessibilityNeed.none,
    localBias: 0.35,
  ),
  DiscoveryScenario(
    id: 'one-hour',
    label: 'Just an hour',
    caption: 'One tight, cheap stop',
    minutes: 60,
    budget: 500,
    interests: {ExperienceCategory.food},
    group: GroupType.solo,
    accessibility: AccessibilityNeed.lowWalking,
    localBias: 0.2,
  ),
  DiscoveryScenario(
    id: 'rainy-evening',
    label: 'Rainy afternoon',
    caption: 'Indoor-first ranking',
    minutes: 180,
    budget: 1200,
    interests: {
      ExperienceCategory.culture,
      ExperienceCategory.art,
      ExperienceCategory.history,
    },
    group: GroupType.couple,
    accessibility: AccessibilityNeed.indoorPreferred,
    localBias: 0.3,
    weather: WeatherCondition.rain,
  ),
  DiscoveryScenario(
    id: 'family-outing',
    label: 'Family outing',
    caption: 'Low walking, all ages',
    minutes: 150,
    budget: 1500,
    interests: {
      ExperienceCategory.culture,
      ExperienceCategory.history,
      ExperienceCategory.nature,
    },
    group: GroupType.family,
    accessibility: AccessibilityNeed.lowWalking,
    localBias: 0.25,
  ),
  DiscoveryScenario(
    id: 'local-deep-dive',
    label: 'Local deep dive',
    caption: 'Skip the tourist trail',
    minutes: 240,
    budget: 2000,
    interests: {
      ExperienceCategory.localLife,
      ExperienceCategory.food,
      ExperienceCategory.art,
    },
    group: GroupType.friends,
    accessibility: AccessibilityNeed.none,
    localBias: 0.02,
  ),
];

final discoveryContextProvider =
    NotifierProvider<DiscoveryContextController, DiscoveryContext>(
  DiscoveryContextController.new,
  name: 'localiq.discoveryContext',
);

/// Live weather + traffic for the active location.
final liveContextProvider = FutureProvider<
    ({WeatherSnapshot weather, TrafficSnapshot traffic})>((ref) async {
  // Re-resolve whenever the centre moves or the what-if lab overrides weather.
  final context = ref.watch(discoveryContextProvider);
  final override = ref.watch(weatherOverrideProvider);
  final repo = ref.watch(contextRepositoryProvider);

  final live = await repo.liveContext(context.centre);
  if (override == null) return live;

  return (
    weather: _applyOverride(live.weather, override),
    traffic: live.traffic,
  );
}, name: 'localiq.liveContext');

/// Rebuilds a snapshot for a different condition, used only by the what-if lab.
WeatherSnapshot _applyOverride(WeatherSnapshot base, WeatherCondition condition) {
  final isWet = condition == WeatherCondition.rain ||
      condition == WeatherCondition.storm;
  return WeatherSnapshot(
    temperatureC: switch (condition) {
      WeatherCondition.clear => 31,
      WeatherCondition.hot => 36,
      WeatherCondition.cloudy => 29,
      WeatherCondition.rain => 27,
      WeatherCondition.storm => 25,
    }.toDouble(),
    condition: condition,
    apparentTemperatureC: switch (condition) {
      WeatherCondition.clear => 33,
      WeatherCondition.hot => 39,
      WeatherCondition.cloudy => 28,
      WeatherCondition.rain => 25,
      WeatherCondition.storm => 23,
    }.toDouble(),
    humidity: isWet ? 84 : 60,
    precipitationChance: isWet ? 78 : 10,
    windKph: isWet ? 26 : 12,
    uvIndex: condition == WeatherCondition.clear ? 9 : 4,
    observedAt: base.observedAt,
    sunrise: base.sunrise,
    sunset: base.sunset,
  );
}
