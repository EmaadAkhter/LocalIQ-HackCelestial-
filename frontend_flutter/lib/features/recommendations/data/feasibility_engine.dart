import 'dart:math' as math;

import '../../context/domain/context_models.dart';
import '../../context/domain/discovery_context.dart';
import '../../places/domain/place.dart';
import '../domain/recommendation.dart';
import '../domain/recommendation_engine.dart';

/// The feasibility-first ranking engine.
///
/// Design rules this implementation holds itself to:
///
///  1. **Hard constraints produce hard failures.** Time, budget, opening
///     hours, weather tolerance and accessibility are never averaged away.
///  2. **Rank ≠ filter.** Every candidate is returned and scored; the tier
///     communicates suitability, the score communicates ordering.
///  3. **Never popularity-led.** Footfall is a weak prior. Fit to the
///     user's actual constraints dominates the score.
///  4. **Reasoning is first-class.** Every score carries the constraint
///     results that produced it, so the UI never has to invent an excuse.
class FeasibilityEngine implements RecommendationEngine {
  FeasibilityEngine({this.baseWalkKmh = 4.6, this.baseSpeedKmh = 22.0});

  /// Average urban walking speed.
  final double baseWalkKmh;

  /// Average door-to-door speed when driving or riding transit.
  final double baseSpeedKmh;

  @override
  Future<TravelEstimate> estimateTravel({
    required LatLng from,
    required Place place,
    required TrafficSnapshot traffic,
  }) async {
    final km = _distance(from, place.pin);
    return _estimate(km, place.pin, from, traffic);
  }

  @override
  Future<RecommendationResult> recommend(
    RecommendationRequest request,
  ) async {
    final context = request.context;
    final scored = <Recommendation>[];

    for (final candidate in request.candidates) {
      final place = candidate.place;
      final experience = candidate.experience;

      // ---- Resolve travel under live traffic -----------------------------
      final outbound = _estimate(
        _distance(context.pin, place.pin),
        place.pin,
        context.pin,
        request.traffic,
      );
      final returnLeg = _estimate(
        _distance(place.pin, context.pin),
        context.pin,
        place.pin,
        request.traffic,
      );

      // ---- Evaluate every constraint explicitly --------------------------
      final constraints = <ConstraintResult>[
        _timeConstraint(context, experience, outbound, returnLeg),
        _budgetConstraint(context, experience),
        _hoursConstraint(context, place),
        _weatherConstraint(request.weather, experience, place),
        _accessibilityConstraint(context, place, outbound),
        _travelConstraint(context, outbound),
        _groupConstraint(context, experience, place),
        _interestConstraint(context, experience, place),
        _crowdConstraint(place),
        _bookingConstraint(place),
      ];

      final tier = _tierFor(constraints);
      final score = _score(
        experience: experience,
        place: place,
        constraints: constraints,
        context: context,
        weather: request.weather,
        outbound: outbound,
        excluded: request.excludedExperienceIds.contains(experience.id),
        query: request.query,
      );

      scored.add(
        Recommendation(
          experience: experience,
          place: place,
          tier: tier,
          constraints: constraints,
          outboundTravel: outbound,
          returnTravel: returnLeg,
          score: score,
          rank: 0,
          whyFits: _whyFits(experience, constraints, context),
          whyRanked: _whyRanked(
            experience: experience,
            constraints: constraints,
            context: context,
            score: score,
            tier: tier,
          ),
          matchReasons: _matchReasons(experience, outbound, place),
          completableMinutes: outbound.minutes +
              experience.activityMinutes +
              returnLeg.minutes,
        ),
      );
    }

    scored.sort((a, b) {
      // Tier dominates ordering; within a tier, score decides.
      final byTier = a.tier.index.compareTo(b.tier.index);
      if (byTier != 0) return byTier;
      return b.score.compareTo(a.score);
    });

    final limited = scored.take(request.limit).toList();
    final ranked = [
      for (var i = 0; i < limited.length; i++)
        _withRank(limited[i], i + 1),
    ];

    return RecommendationResult(
      recommendations: ranked,
      evaluatedCount: scored.length,
      context: context,
      generatedAt: DateTime.now(),
    );
  }

  // ------------------------------------------------------------------ travel

  TravelEstimate _estimate(
    double km,
    LatLng to,
    LatLng from,
    TrafficSnapshot traffic,
  ) {
    final mode = km < 1.2
        ? TravelMode.walk
        : km < 4.5
            ? TravelMode.transit
            : TravelMode.taxi;
    final speed = switch (mode) {
      TravelMode.walk => baseWalkKmh,
      TravelMode.bike => 14,
      TravelMode.transit => baseSpeedKmh * 0.72,
      TravelMode.taxi => baseSpeedKmh,
    };
    final baseline = ((km / speed) * 60).round();
    final adjusted = mode == TravelMode.walk
        ? baseline
        : traffic.adjust(baseline);
    return TravelEstimate(
      minutes: math.max(2, adjusted),
      distanceKm: km,
      mode: mode,
      baselineMinutes: math.max(2, baseline),
      trafficLevel: traffic.level,
    );
  }

  static double _distance(
    LatLng a,
    LatLng b,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _rad(b.lat - a.lat);
    final dLng = _rad(b.lng - a.lng);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) *
            math.sin(dLng / 2) *
            math.cos(_rad(a.lat)) *
            math.cos(_rad(b.lat));
    return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
  }

  static double _rad(double degrees) => degrees * math.pi / 180.0;

  // ------------------------------------------------------------- constraints

  ConstraintResult _timeConstraint(
    DiscoveryContext context,
    Experience experience,
    TravelEstimate outbound,
    TravelEstimate returnLeg,
  ) {
    final full = outbound.minutes + experience.activityMinutes + returnLeg.minutes;
    final essential = outbound.minutes + experience.minimumMinutes + returnLeg.minutes;
    final available = context.timeBudgetMinutes;

    if (full <= available) {
      return ConstraintResult.pass(
        ConstraintKind.time,
        'Fits your window',
        '${DiscoveryContext.formatMinutes(full)} door to door, '
            '${available - full} min spare',
      );
    }
    if (essential <= available) {
      return ConstraintResult.warn(
        ConstraintKind.time,
        'Needs trimming',
        'Full visit is ${DiscoveryContext.formatMinutes(full)}; the '
            '${experience.minimumMinutes}-minute essential version fits',
      );
    }
    return ConstraintResult.fail(
      ConstraintKind.time,
      'Not enough time',
      'Needs ${DiscoveryContext.formatMinutes(essential)} minimum, you have '
          '${DiscoveryContext.formatMinutes(available)}',
    );
  }

  ConstraintResult _budgetConstraint(
    DiscoveryContext context,
    Experience experience,
  ) {
    final cost = experience.typicalSpend;
    if (cost == 0) {
      return ConstraintResult.pass(
        ConstraintKind.budget,
        'Free to enter',
        'No ticket or minimum spend',
      );
    }
    if (cost <= context.budget) {
      return ConstraintResult.pass(
        ConstraintKind.budget,
        'Within budget',
        '${experience.priceLabel} of ${context.budgetLabel}',
      );
    }
    if (cost <= context.budget * 1.35) {
      return ConstraintResult.warn(
        ConstraintKind.budget,
        'Slightly over',
        '${experience.priceLabel} is ${cost - context.budget} over '
            '${context.budgetLabel}',
      );
    }
    return ConstraintResult.fail(
      ConstraintKind.budget,
      'Over budget',
      '${experience.priceLabel} against a ${context.budgetLabel} budget',
    );
  }

  ConstraintResult _hoursConstraint(
    DiscoveryContext context,
    Place place,
  ) {
    final arrive = context.startTime;
    final depart = context.endTime;
    final hours = place.openingHours;

    if (!hours.isOpenAt(arrive)) {
      return ConstraintResult.fail(
        ConstraintKind.openingHours,
        'Closed when you arrive',
        hours.describeFor(arrive),
      );
    }
    final closeMinutes = hours.closeMinutesFor(arrive);
    if (closeMinutes == null) {
      return ConstraintResult.fail(
        ConstraintKind.openingHours,
        'Closed when you arrive',
        hours.describeFor(arrive),
      );
    }
    final closeAt = DateTime(
      arrive.year,
      arrive.month,
      arrive.day,
      closeMinutes ~/ 60,
      closeMinutes % 60,
    );
    if (depart.isAfter(closeAt)) {
      return ConstraintResult.fail(
        ConstraintKind.openingHours,
        'Closes before you finish',
        'Your window ends ${_clock(depart)}, it closes ${_clock(closeAt)}',
      );
    }
    // Less than 30 minutes of usable time before closing is a soft warning.
    final slack = closeAt.difference(depart).inMinutes;
    if (slack < 30) {
      return ConstraintResult.warn(
        ConstraintKind.openingHours,
        'Tight before closing',
        'Only $slack min of margin before ${_clock(closeAt)}',
      );
    }
    return ConstraintResult.pass(
      ConstraintKind.openingHours,
      'Open for your window',
      hours.describeFor(arrive),
    );
  }

  ConstraintResult _weatherConstraint(
    WeatherSnapshot weather,
    Experience experience,
    Place place,
  ) {
    if (!weather.isWet) {
      if (weather.condition == WeatherCondition.hot && !place.indoor) {
        return ConstraintResult.warn(
          ConstraintKind.weather,
          'Exposed to the heat',
          '${weather.temperatureLabel} with no shade on this route',
        );
      }
      return ConstraintResult.pass(
        ConstraintKind.weather,
        'Weather is fine',
        weather.planningNote,
      );
    }

    if (experience.toleratesRain && place.indoor) {
      return ConstraintResult.pass(
        ConstraintKind.weather,
        'Rain-proof',
        'Indoor and covered — ${weather.planningNote.toLowerCase()}',
      );
    }
    if (experience.weatherSuitability == WeatherSuitability.sheltered) {
      return ConstraintResult.warn(
        ConstraintKind.weather,
        'Partly sheltered',
        'Some exposed sections even in light rain',
      );
    }
    // A sheltered but outdoor option keeps the weather rule as its only
    // failure, which surfaces as "partially suitable" rather than blocked.
    return ConstraintResult.fail(
      ConstraintKind.weather,
      'Weather unsuitable',
      '${experience.weatherSuitability.label} in '
          '${weather.condition.label.toLowerCase()} '
          '(${weather.precipitationChance}% chance of rain)',
    );
  }

  ConstraintResult _accessibilityConstraint(
    DiscoveryContext context,
    Place place,
    TravelEstimate outbound,
  ) {
    final need = context.accessibility;
    final access = place.accessibility;
    final walking = outbound.mode == TravelMode.walk;

    if (need == AccessibilityNeed.wheelchair) {
      if (access.wheelchairAccessible) {
        return ConstraintResult.pass(
          ConstraintKind.accessibility,
          'Wheelchair accessible',
          'Step-free entry and accessible facilities',
        );
      }
      return ConstraintResult.fail(
        ConstraintKind.accessibility,
        'Accessibility mismatch',
        'Not a wheelchair-accessible route',
      );
    }
    if (need == AccessibilityNeed.stepFree && !access.stepFree) {
      return ConstraintResult.fail(
        ConstraintKind.accessibility,
        'Stairs on the route',
        access.notes ?? 'Approach includes steps or uneven ground',
      );
    }
    if (need == AccessibilityNeed.lowWalking) {
      if (walking && outbound.minutes > access.maxWalkingMinutes) {
        return ConstraintResult.fail(
          ConstraintKind.accessibility,
          'Too much walking',
          '${outbound.minutes} min walk vs a '
              '${access.maxWalkingMinutes} min limit',
        );
      }
      return ConstraintResult.pass(
        ConstraintKind.accessibility,
        'Low walking',
        walking
            ? '${outbound.minutes} min on foot, within your limit'
            : 'Reachable without a long walk',
      );
    }
    if (need == AccessibilityNeed.indoorPreferred && !place.indoor) {
      return ConstraintResult.warn(
        ConstraintKind.accessibility,
        'Outdoor stop',
        'You asked for indoor-first; this one is open air',
      );
    }
    return ConstraintResult.pass(
      ConstraintKind.accessibility,
      'Route works',
      access.notes ?? 'Standard access',
    );
  }

  ConstraintResult _travelConstraint(
    DiscoveryContext context,
    TravelEstimate outbound,
  ) {
    if (outbound.minutes <= context.maxTravelMinutes) {
      return ConstraintResult.pass(
        ConstraintKind.travelTime,
        'Comfortable journey',
        '${outbound.label} by ${outbound.mode.label.toLowerCase()}',
      );
    }
    return ConstraintResult.fail(
      ConstraintKind.travelTime,
      'Travel time too high',
      '${outbound.minutes} min each way is most of your window',
    );
  }

  ConstraintResult _groupConstraint(
    DiscoveryContext context,
    Experience experience,
    Place place,
  ) {
    final group = context.groupType;
    final longWindow = experience.activityMinutes >= 75;

    switch (group) {
      case GroupType.family:
        if (longWindow) {
          return ConstraintResult.warn(
            ConstraintKind.group,
            'Long for a family outing',
            '${experience.activityMinutes} min without a break',
          );
        }
        if (!place.accessibility.seatingAvailable) {
          return ConstraintResult.warn(
            ConstraintKind.group,
            'Limited seating',
            'Harder to settle in with a group',
          );
        }
        return ConstraintResult.pass(
          ConstraintKind.group,
          'Family friendly',
          '${experience.activityMinutes} min with seating available',
        );
      case GroupType.couple:
        if (place.crowdLevel == CrowdLevel.veryBusy) {
          return ConstraintResult.warn(
            ConstraintKind.group,
            'Very crowded for two',
            'Expect little space to settle',
          );
        }
        return ConstraintResult.pass(
          ConstraintKind.group,
          'Works for two',
          place.localFavourite ? 'Quieter, locals-favoured spot' : 'Easy to reach together',
        );
      case GroupType.friends:
        if (experience.category == ExperienceCategory.wellness) {
          return ConstraintResult.warn(
            ConstraintKind.group,
            'Calmer than most groups want',
            'Fine, but not a typical group pick',
          );
        }
        return ConstraintResult.pass(
          ConstraintKind.group,
          'Group friendly',
          'Flexible timing, easy to extend',
        );
      case GroupType.team:
        if (longWindow || place.bookingRequired) {
          return ConstraintResult.warn(
            ConstraintKind.group,
            'Harder to schedule',
            'Needs a firm start time',
          );
        }
        return ConstraintResult.pass(
          ConstraintKind.group,
          'Easy to schedule',
          'Walk-in, no booking',
        );
      case GroupType.solo:
        return ConstraintResult.pass(
          ConstraintKind.group,
          'Easy solo',
          'No booking or coordination needed',
        );
    }
  }

  ConstraintResult _interestConstraint(
    DiscoveryContext context,
    Experience experience,
    Place place,
  ) {
    if (context.interests.isEmpty) return _pass(ConstraintKind.interest, 'Open to anything', 'No interest filter applied');
    if (context.interests.contains(experience.category)) {
      return ConstraintResult.pass(
        ConstraintKind.interest,
        'Matches your interests',
        '${experience.category.label} is one of your picks',
      );
    }
    if (context.interests.contains(place.category)) {
      return ConstraintResult.warn(
        ConstraintKind.interest,
        'Adjacent to your interests',
        '${place.category.label} rather than ${experience.category.label}',
      );
    }
    return ConstraintResult.fail(
      ConstraintKind.interest,
      'Outside your interests',
      'You picked ${context.interestsLabel}, this is '
          '${experience.category.label.toLowerCase()}',
    );
  }

  ConstraintResult _crowdConstraint(Place place) {
    if (place.crowdLevel == CrowdLevel.veryBusy) {
      return ConstraintResult.warn(
        ConstraintKind.crowd,
        'Very busy right now',
        'Expect queues and little personal space',
      );
    }
    if (place.crowdLevel == CrowdLevel.quiet) {
      return ConstraintResult.pass(
        ConstraintKind.crowd,
        'Quiet right now',
        'Uncrowded, so you will not queue',
      );
    }
    return _pass(ConstraintKind.crowd, 'Normal crowd', place.crowdLevel.label);
  }

  ConstraintResult _bookingConstraint(Place place) {
    if (place.bookingRequired) {
      return ConstraintResult.warn(
        ConstraintKind.booking,
        'Booking needed',
        place.summary ?? 'Reserve ahead to secure a slot',
      );
    }
    return _pass(ConstraintKind.booking, 'Walk-in', 'No reservation required');
  }

  ConstraintResult _pass(ConstraintKind kind, String title, String detail) {
    return ConstraintResult.pass(kind, title, detail);
  }

  // ------------------------------------------------------------------- tier

  FeasibilityTier _tierFor(List<ConstraintResult> constraints) {
    if (constraints.any((c) => c.isBlocking)) {
      // Not every failure is equally fatal. A single soft mismatch can still
      // be presented as partially suitable.
      final hardFailures = constraints.where((c) => c.isBlocking).length;
      if (hardFailures == 1) return FeasibilityTier.partial;
      return FeasibilityTier.notFeasible;
    }
    if (constraints.any((c) => c.isCaveat)) return FeasibilityTier.partial;
    return FeasibilityTier.feasible;
  }

  // ------------------------------------------------------------------ score

  /// Relevance score, built as a weighted average of named components rather
  /// than a sum of bonuses.
  ///
  /// Summing bonuses saturates: once several bonuses stack, every option pins
  /// at the 100 ceiling and the ordering silently degrades to insertion order.
  /// Averaging bounded components guarantees the full 0–100 range is used, and
  /// keeps every term legible in [whyRanked].
  double _score({
    required Experience experience,
    required Place place,
    required List<ConstraintResult> constraints,
    required DiscoveryContext context,
    required WeatherSnapshot weather,
    required TravelEstimate outbound,
    required bool excluded,
    String? query,
  }) {
    // --- 1. Window fit (weight 26) ----------------------------------------
    // Rewards plans that comfortably fill the window without travel
    // dominating it. A stop that spends half the window on transit is weak.
    final doorToDoor = outbound.minutes * 2 + experience.activityMinutes;
    final windowUse = doorToDoor / math.max(1, context.timeBudgetMinutes);
    final travelShare =
        outbound.minutes / math.max(1, context.timeBudgetMinutes);
    final windowFit = (1 - (windowUse * 0.6 + travelShare * 0.8))
        .clamp(0.0, 1.0);

    // --- 2. Local ↔ tourist axis (weight 22) ------------------------------
    final axisScore =
        (experience.localScore / 100) * (1 - context.localBias) +
            (experience.touristScore / 100) * context.localBias;

    // --- 3. Interest alignment (weight 16) ---------------------------------
    double interestFit;
    if (context.interests.isEmpty) {
      interestFit = 0.5;
    } else if (context.interests.contains(experience.category)) {
      interestFit = 1;
    } else if (context.interests.contains(place.category)) {
      interestFit = 0.6;
    } else {
      interestFit = 0.1;
    }

    // --- 4. Budget fit (weight 12) ----------------------------------------
    // Free is perfect; filling the budget exactly is also fine. Over is zero.
    final budgetFit = experience.typicalSpend == 0
        ? 1.0
        : (1 - experience.typicalSpend / math.max(1, context.budget * 1.25))
            .clamp(0.0, 1.0);

    // --- 5. Weather fit (weight 12) ---------------------------------------
    final weatherFit = weather.isWet
        ? (experience.toleratesRain ? (place.indoor ? 1.0 : 0.55) : 0.0)
        : (place.indoor ? 0.5 : 1.0);

    // --- 6. Quality prior (weight 7) --------------------------------------
    // Deliberately small so ratings and footfall never lead the ranking.
    final qualityFit = (((experience.localScore + place.rating * 20) / 2) / 100)
        .clamp(0.0, 1.0);

    // --- 7. Ease of visit (weight 5) --------------------------------------
    var ease = 0.6;
    if (experience.flexibleTiming) ease += 0.1;
    if (place.crowdLevel == CrowdLevel.quiet) ease += 0.15;
    if (place.crowdLevel == CrowdLevel.busy) ease -= 0.05;
    if (place.crowdLevel == CrowdLevel.veryBusy) ease -= 0.2;
    if (place.bookingRequired) ease -= 0.15;
    ease = ease.clamp(0.0, 1.0);

    // --- 8. Constraint cleanliness (weight 4) -----------------------------
    final clean =
        (1 - constraints.where((c) => c.status != ConstraintStatus.pass).length * 0.3)
            .clamp(0.0, 1.0);

    var score =
        windowFit * 26 +
        axisScore * 22 +
        interestFit * 16 +
        budgetFit * 12 +
        weatherFit * 12 +
        qualityFit * 7 +
        ease * 5 +
        clean * 4;

    // --- Modifiers ---------------------------------------------------------
    // Already in the plan: surfaced, but below unseen options.
    if (excluded) score -= 6;

    // Natural-language intent is a hard filter upstream, so here it only
    // breaks ties between otherwise equal candidates.
    final text = (query ?? context.query).trim().toLowerCase();
    if (text.isNotEmpty) {
      final haystack =
          '${experience.title} ${experience.description} ${place.name} '
          '${place.area} ${place.summary ?? ''}'.toLowerCase();
      var hits = 0;
      for (final token in text.split(RegExp(r'[^a-z0-9₹]+'))) {
        if (token.length > 2 && haystack.contains(token)) hits++;
      }
      score += (hits * 2.5).clamp(0, 7);
    }

    return score.clamp(0, 100);
  }

  // ------------------------------------------------------------ explanation

  List<String> _whyFits(
    Experience experience,
    List<ConstraintResult> constraints,
    DiscoveryContext context,
  ) {
    final reasons = constraints
        .where((c) => c.status == ConstraintStatus.pass)
        .map((c) => c.detail)
        .take(4)
        .toList();
    if (reasons.isEmpty) {
      reasons.add('Nothing clears every constraint right now.');
    }
    return reasons;
  }

  String _whyRanked({
    required Experience experience,
    required List<ConstraintResult> constraints,
    required DiscoveryContext context,
    required double score,
    required FeasibilityTier tier,
  }) {
    final strengths = constraints
        .where((c) => c.status == ConstraintStatus.pass)
        .map((c) => c.title)
        .toList();
    final tradeoffs = constraints
        .where((c) => c.status == ConstraintStatus.warn)
        .map((c) => c.title)
        .toList();

    final buffer = switch (tier) {
      FeasibilityTier.feasible =>
        'a ${_bufferLabel(constraints, context)} buffer',
      FeasibilityTier.partial => 'trade-offs on ${tradeoffs.join(', ')}',
      FeasibilityTier.notFeasible =>
        'blocked by ${constraints.where((c) => c.isBlocking).map((c) => c.title).join(', ')}',
    };

    final axis = context.localBias < 0.35
        ? 'Rated highly by locals'
        : context.localBias > 0.65
            ? 'A well-known landmark'
            : 'Balanced local/visitor appeal';

    return '$axis. Ranked on ${strengths.take(3).join(', ')} with $buffer.';
  }

  String _bufferLabel(List<ConstraintResult> constraints, DiscoveryContext context) {
    final time = constraints.firstWhere(
      (c) => c.kind == ConstraintKind.time,
      orElse: () => ConstraintResult.pass(ConstraintKind.time, '', ''),
    );
    final match = RegExp(r'(\d+) min spare').firstMatch(time.detail);
    final spare = match != null ? int.parse(match.group(1)!) : 0;
    if (spare <= 0) return 'an exact fit';
    if (spare < 20) return 'a $spare-minute';
    return 'a comfortable $spare-minute';
  }

  List<String> _matchReasons(
    Experience experience,
    TravelEstimate outbound,
    Place place,
  ) {
    return [
      '${outbound.minutes} min away',
      '${experience.activityMinutes} min there',
      experience.priceLabel,
      if (place.indoor) 'Indoor' else 'Outdoor',
      if (place.localFavourite) 'Local favourite',
    ];
  }

  Recommendation _withRank(Recommendation rec, int rank) {
    return Recommendation(
      experience: rec.experience,
      place: rec.place,
      tier: rec.tier,
      constraints: rec.constraints,
      outboundTravel: rec.outboundTravel,
      returnTravel: rec.returnTravel,
      score: rec.score,
      rank: rank,
      whyFits: rec.whyFits,
      whyRanked: rec.whyRanked,
      matchReasons: rec.matchReasons,
      completableMinutes: rec.completableMinutes,
    );
  }

  static String _clock(DateTime time) {
    final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m ${time.hour >= 12 ? 'PM' : 'AM'}';
  }
}
