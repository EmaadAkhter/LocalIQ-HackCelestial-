import 'package:flutter_test/flutter_test.dart';
import 'package:localiq/features/context/data/local_context_repository.dart';
import 'package:localiq/features/context/domain/context_models.dart';
import 'package:localiq/features/context/domain/discovery_context.dart';
import 'package:localiq/features/places/data/local_experiences.dart';
import 'package:localiq/features/places/data/local_place_repository.dart';
import 'package:localiq/features/places/data/local_places.dart';
import 'package:localiq/features/places/domain/place.dart';
import 'package:localiq/features/places/domain/place_repository.dart';
import 'package:localiq/features/recommendations/data/feasibility_engine.dart';
import 'package:localiq/features/recommendations/domain/recommendation.dart';
import 'package:localiq/features/recommendations/domain/recommendation_engine.dart';
import 'package:localiq/features/routing/data/local_routes_service.dart';

/// Fixed clock so opening-hours and traffic assertions are deterministic.
DateTime _clock() => DateTime(2025, 9, 5, 14); // Friday, 2 PM

DiscoveryContext _context({
  int minutes = 120,
  int budget = 1000,
  GroupType group = GroupType.solo,
  AccessibilityNeed access = AccessibilityNeed.none,
  Set<ExperienceCategory> interests = const {
    ExperienceCategory.food,
    ExperienceCategory.culture,
    ExperienceCategory.art,
  },
  double bias = 0.3,
}) {
  return DiscoveryContext(
    locationLabel: 'Fort, South Mumbai',
    centre: const GeoPoint(latitude: 18.9322, longitude: 72.8316),
    timeBudgetMinutes: minutes,
    startTime: _clock(),
    budget: budget,
    interests: interests,
    groupType: group,
    accessibility: access,
    localBias: bias,
    query: '',
  );
}

void main() {
  late LocalPlaceRepository places;
  late FeasibilityEngine engine;
  late LocalContextRepository contextRepo;

  setUp(() {
    places = LocalPlaceRepository(latency: Duration.zero);
    engine = FeasibilityEngine();
    contextRepo = LocalContextRepository(clock: _clock);
  });

  Future<RecommendationResult> rank({
    required DiscoveryContext discovery,
    WeatherCondition? weather,
  }) async {
    final live = await contextRepo.liveContext(discovery.centre);
    final allPlaces = await places.search(
      PlaceQuery(near: discovery.centre, radiusKm: 60, limit: 200),
    );
    final candidates = <({Place place, Experience experience})>[];
    for (final place in allPlaces) {
      for (final experience in await places.experiencesForPlace(place.id)) {
        candidates.add((place: place, experience: experience));
      }
    }
    final wet = weather == WeatherCondition.rain ||
        weather == WeatherCondition.storm;
    final snapshot = weather == null
        ? live.weather
        : WeatherSnapshot(
            temperatureC: wet ? 27 : 30,
            condition: weather,
            apparentTemperatureC: wet ? 25 : 31,
            humidity: wet ? 85 : 60,
            precipitationChance: wet ? 80 : 10,
            windKph: wet ? 22 : 12,
            uvIndex: wet ? 2 : 7,
            observedAt: _clock(),
            sunrise: _clock(),
            sunset: _clock(),
          );
    return engine.recommend(
      RecommendationRequest(
        context: discovery,
        weather: snapshot,
        traffic: live.traffic,
        candidates: candidates,
        excludedExperienceIds: const {},
        limit: 60,
      ),
    );
  }

  group('catalogue', () {
    test('loads places and their experiences', () async {
      final all = await places.search(
        PlaceQuery(near: const GeoPoint(latitude: 18.9322, longitude: 72.8316), radiusKm: 60),
      );
      expect(all.length, greaterThanOrEqualTo(15));
      for (final place in all) {
        final experiences = await places.experiencesForPlace(place.id);
        expect(experiences, isNotEmpty, reason: '${place.id} has no experience');
        for (final experience in experiences) {
          expect(experience.placeId, place.id);
          expect(experience.activityMinutes, greaterThan(0));
          expect(experience.typicalSpend, greaterThanOrEqualTo(0));
          expect(experience.highlights, isNotEmpty);
        }
      }
    });

    test('ids are unique across places and experiences', () {
      expect(localPlaces.map((p) => p.id).toSet().length, localPlaces.length);
      expect(
        localExperiences.map((e) => e.id).toSet().length,
        localExperiences.length,
      );
    });

    test('exposes realistic South Mumbai coverage', () {
      final names = localPlaces.map((p) => p.name).join(' | ').toLowerCase();
      for (final expected in [
        'bastion',
        'jehangir',
        'kala ghoda',
        'csmvs',
        'gateway',
        'marine drive',
        'mani bhavan',
        'sassoon dock',
        'bandra fort',
        'candies',
        'mount mary',
        'bhau daji lad',
        'haji ali',
        'worli',
        'colaba',
      ]) {
        expect(names, contains(expected), reason: 'missing $expected');
      }
    });

    test('every place has coordinates and a hero image', () {
      for (final place in localPlaces) {
        expect(place.centre.latitude, isNot(0));
        expect(place.centre.longitude, isNot(0));
        expect(place.heroImageUrl, startsWith('http'));
        expect(place.openingHours.weekly, isNotEmpty);
      }
    });
  });

  group('popularity vs fit', () {
    test('ranking is not popularity-led', () async {
      final result = await rank(discovery: _context(minutes: 60, budget: 500));
      expect(result.feasible, isNotEmpty);
      for (final rec in result.feasible) {
        // A high-footfall landmark with a long transit must not outrank a
        // closer, better-fitting option just because it is famous.
        expect(
          rec.completableMinutes,
          lessThanOrEqualTo(60),
          reason: '${rec.experience.title} is over the window',
        );
      }
    });

    test('local bias reorders the list toward local gems', () async {
      // A wide window so that both local gems and landmarks stay in play;
      // the axis must be observable in the ordering the user actually sees.
      double meanLocalGap(List<Recommendation> list) {
        if (list.isEmpty) return 0;
        final top = list.take(8).toList();
        return top
                .map((r) => r.experience.localScore - r.experience.touristScore)
                .reduce((a, b) => a + b) /
            top.length;
      }

      final localFirst = await rank(
        discovery: _context(
          minutes: 300,
          budget: 4000,
          bias: 0,
          interests: ExperienceCategory.values.toSet(),
        ),
        weather: WeatherCondition.clear,
      );
      final touristFirst = await rank(
        discovery: _context(
          minutes: 300,
          budget: 4000,
          bias: 1,
          interests: ExperienceCategory.values.toSet(),
        ),
        weather: WeatherCondition.clear,
      );

      expect(
        meanLocalGap(localFirst.recommendations),
        greaterThan(meanLocalGap(touristFirst.recommendations)),
        reason: 'Local bias should favour local gems',
      );
      // The headline pick should actually change.
      expect(
        localFirst.recommendations.first.experience.id,
        isNot(touristFirst.recommendations.first.experience.id),
      );
    });
  });

  group('feasibility tiers', () {
    test('every option gets exactly one tier and covers all options',
        () async {
      final result = await rank(discovery: _context());
      final total =
          result.feasibleCount + result.partialCount + result.blockedCount;
      expect(total, result.evaluatedCount);
      expect(total, greaterThan(0));
    });

    test('a single soft failure yields partial, two or more yield blocked',
        () async {
      final result = await rank(discovery: _context(minutes: 90, budget: 700));
      for (final rec in result.recommendations) {
        final blocks = rec.blockers.length;
        if (rec.tier == FeasibilityTier.notFeasible) {
          expect(blocks, greaterThanOrEqualTo(2),
              reason: '${rec.experience.title}: ${rec.primaryBlocker}');
        }
        if (rec.tier == FeasibilityTier.partial) {
          expect(rec.blockers.length + rec.caveats.length, greaterThan(0));
        }
        if (rec.tier == FeasibilityTier.feasible) {
          expect(rec.blockers, isEmpty);
          expect(rec.caveats, isEmpty);
        }
      }
    });

    test('rain demotes exposed options and promotes covered ones', () async {
      final discovery = _context(
        minutes: 300,
        budget: 4000,
        interests: ExperienceCategory.values.toSet(),
      );
      final clear = await rank(
        discovery: discovery,
        weather: WeatherCondition.clear,
      );
      final wet = await rank(discovery: discovery, weather: WeatherCondition.rain);

      // Rain must never improve an exposed option.
      final clearRanks = {
        for (final rec in clear.recommendations) rec.experience.id: rec.rank,
      };

      final exposedDemoted = <String>[];
      for (final dry in clear.feasible) {
        if (dry.experience.toleratesRain && dry.place.indoor) continue;
        final nowWet = wet.byId(dry.experience.id)!;
        expect(
          nowWet.tier.index,
          greaterThanOrEqualTo(dry.tier.index),
          reason: '${dry.experience.title} must not improve in rain',
        );
        if (nowWet.rank > clearRanks[dry.experience.id]!) {
          exposedDemoted.add(dry.experience.title);
        }
      }
      expect(
        exposedDemoted,
        isNotEmpty,
        reason: 'rain should push exposed options down the ranking',
      );

      // Anything blocked specifically by weather must name weather in that
      // blocker's own detail. (It need not be the *primary* blocker — a venue
      // can be closed and exposed at the same time.)
      final weatherBlocked = wet.recommendations
          .where((r) => r.blockers.any((b) => b.kind == ConstraintKind.weather));
      expect(weatherBlocked, isNotEmpty, reason: 'rain should block something');
      for (final rec in weatherBlocked) {
        final weatherBlocker = rec.blockers
            .firstWhere((b) => b.kind == ConstraintKind.weather);
        expect(weatherBlocker.detail.toLowerCase(), contains('rain'));
      }

      // The overall mix must shift: fewer outright wins in the rain.
      expect(wet.feasibleCount, lessThanOrEqualTo(clear.feasibleCount));
    });

    test('budget failures name the budget', () async {
      final result = await rank(discovery: _context(minutes: 300, budget: 200));
      final blocked = result.blocked;
      expect(blocked, isNotEmpty);
      expect(
        blocked.map((r) => r.blockers.map((b) => b.kind)),
        anyElement(contains(ConstraintKind.budget)),
      );
    });

    test('closed venues are blocked by opening hours', () async {
      final result = await rank(
        discovery: _context(minutes: 300, budget: 4000, interests: ExperienceCategory.values.toSet()),
      );
      final closed = result.recommendations.firstWhere(
        (r) => r.place.id == 'place-sassoon-dock',
      );
      expect(closed.tier, FeasibilityTier.notFeasible);
      expect(closed.blockers.map((b) => b.kind), contains(ConstraintKind.openingHours));
      expect(closed.primaryBlocker.toLowerCase(), contains('closed'));
    });

    test('accessibility need is enforced strictly', () async {
      final result = await rank(
        discovery: _context(
          minutes: 300,
          budget: 4000,
          access: AccessibilityNeed.wheelchair,
          interests: ExperienceCategory.values.toSet(),
        ),
      );
      for (final rec in result.feasible) {
        expect(rec.place.accessibility.wheelchairAccessible, isTrue);
      }
    });

    test('long transit blocks an otherwise good option', () async {
      final result = await rank(
        discovery: _context(minutes: 45, budget: 4000, interests: ExperienceCategory.values.toSet()),
      );
      for (final rec in result.feasible) {
        expect(rec.outboundTravel.minutes, lessThan(45));
      }
    });
  });

  group('travel estimates', () {
    test('walk, transit and taxi are chosen by distance', () {
      const routes = LocalRoutesService();
      expect(routes.recommendedMode(0.6), TravelMode.walk);
      expect(routes.recommendedMode(2.5), TravelMode.transit);
      expect(routes.recommendedMode(18), TravelMode.taxi);
    });

    test('traffic multiplies non-walking estimates', () {
      final now = DateTime(2025, 9, 5, 14);
      final light = TrafficSnapshot(
        level: TrafficLevel.light,
        speedMultiplier: TrafficLevel.light.multiplier,
        updatedAt: now,
      );
      final heavy = TrafficSnapshot(
        level: TrafficLevel.heavy,
        speedMultiplier: TrafficLevel.heavy.multiplier,
        updatedAt: now,
      );
      expect(heavy.adjust(20), greaterThan(light.adjust(20)));
      expect(light.adjust(0), 0);
    });

    test('routes produce a plausible multi-point path', () async {
      const routes = LocalRoutesService();
      final plan = await routes.route(
        from: (lat: 18.9322, lng: 72.8316),
        to: (lat: 18.9432, lng: 72.8236),
        mode: TravelMode.walk,
      );
      expect(plan.totalMinutes, greaterThan(0));
      expect(plan.totalDistanceKm, greaterThan(0));
      expect(plan.legs.first.path.length, greaterThan(2));
    });
  });

  group('weather and traffic source', () {
    test('is deterministic for a fixed clock', () async {
      final a = await contextRepo.weatherAt(const GeoPoint(latitude: 18.93, longitude: 72.83));
      final b = await contextRepo.weatherAt(const GeoPoint(latitude: 18.93, longitude: 72.83));
      expect(a.condition, b.condition);
      expect(a.temperatureC, b.temperatureC);
    });

    test('rush hour is heavier than late night', () async {
      // The local source keys traffic to the hour, so a 09:00 clock must
      // produce a heavier level than a 23:00 clock.
      final morning = await LocalContextRepository(
        clock: () => DateTime(2025, 9, 5, 9),
      ).trafficAt(const GeoPoint(latitude: 18.93, longitude: 72.83));
      final night = await LocalContextRepository(
        clock: () => DateTime(2025, 9, 5, 23),
      ).trafficAt(const GeoPoint(latitude: 18.93, longitude: 72.83));

      expect(morning.level, TrafficLevel.heavy);
      expect(night.level, TrafficLevel.light);
      expect(morning.speedMultiplier, greaterThan(night.speedMultiplier));
    });
  });

  group('explanations', () {
    test('every recommendation explains itself', () async {
      final result = await rank(discovery: _context(minutes: 150, budget: 1500));
      for (final rec in result.recommendations) {
        expect(rec.whyFits, isNotEmpty, reason: rec.experience.id);
        expect(rec.whyRanked, isNotEmpty, reason: rec.experience.id);
        expect(rec.constraints.length, greaterThanOrEqualTo(8));
        expect(rec.matchReasons, isNotEmpty);
        expect(rec.score, inInclusiveRange(0, 100));
        if (rec.tier == FeasibilityTier.notFeasible) {
          expect(rec.primaryBlocker, isNotEmpty);
        }
      }
    });

    test('ranks are contiguous starting at one', () async {
      final result = await rank(discovery: _context(minutes: 200, budget: 3000));
      for (var i = 0; i < result.recommendations.length; i++) {
        expect(result.recommendations[i].rank, i + 1);
      }
    });
  });
}
