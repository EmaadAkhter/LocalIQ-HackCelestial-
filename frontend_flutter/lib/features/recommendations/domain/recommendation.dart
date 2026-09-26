export '../../routing/domain/routes_service.dart' show TravelMode, TravelModeX, TravelEstimate;
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json_map_x.dart';
import '../../context/domain/discovery_context.dart';
import '../../context/domain/context_models.dart';
import '../../places/domain/place.dart';
import '../../routing/domain/routes_service.dart';

/// Canonical coordinate pair. A record is used instead of a class so it
/// composes with map markers and route polylines without adapters.
typedef LatLng = ({double lat, double lng});

/// Extension used by the engine to convert a [Place] centre.
extension PlaceCentre on Place {
  LatLng get pin => (lat: centre.latitude, lng: centre.longitude);
}

/// Three-tier feasibility. This is the core product concept: not "good" and
/// "bad" places, but what the user can *actually* finish right now.
enum FeasibilityTier {
  /// Every hard constraint satisfied.
  feasible('Feasible', 'You can complete this in the time you have.'),

  /// Achievable with a trade-off (shorten, skip an element, or accept a
  /// less ideal option). Actionable by the user.
  partial('Partially suitable', 'Doable, but something has to give.'),

  /// One or more hard constraints fail. Shown with the exact reason.
  notFeasible('Not feasible', 'Cannot be completed under these conditions.');

  const FeasibilityTier(this.label, this.blurb);

  final String label;
  final String blurb;

  Color get color => switch (this) {
        FeasibilityTier.feasible => AppColors.success,
        FeasibilityTier.partial => AppColors.warning,
        FeasibilityTier.notFeasible => AppColors.danger,
      };

  Color get surface => switch (this) {
        FeasibilityTier.feasible => AppColors.successSurface,
        FeasibilityTier.partial => AppColors.warningSurface,
        FeasibilityTier.notFeasible => AppColors.dangerSurface,
      };

  IconData get icon => switch (this) {
        FeasibilityTier.feasible => Icons.verified_rounded,
        FeasibilityTier.partial => Icons.pending_actions_rounded,
        FeasibilityTier.notFeasible => Icons.block_rounded,
      };
}

/// Why a constraint passed or failed. `severity` decides the tier.
enum ConstraintKind {
  time,
  budget,
  openingHours,
  weather,
  accessibility,
  travelTime,
  group,
  interest,
  crowd,
  booking;

  String get label => switch (this) {
        ConstraintKind.time => 'Time',
        ConstraintKind.budget => 'Budget',
        ConstraintKind.openingHours => 'Opening hours',
        ConstraintKind.weather => 'Weather',
        ConstraintKind.accessibility => 'Accessibility',
        ConstraintKind.travelTime => 'Travel time',
        ConstraintKind.group => 'Group fit',
        ConstraintKind.interest => 'Interest match',
        ConstraintKind.crowd => 'Crowd level',
        ConstraintKind.booking => 'Booking',
      };
}

enum ConstraintStatus { pass, warn, fail }

/// One evaluated constraint. Rendered verbatim in the UI so the reasoning is
/// never hidden behind a score.
@immutable
class ConstraintResult {
  const ConstraintResult({
    required this.kind,
    required this.status,
    required this.title,
    required this.detail,
  });

  final ConstraintKind kind;
  final ConstraintStatus status;
  final String title;
  final String detail;

  bool get isBlocking => status == ConstraintStatus.fail;

  bool get isCaveat => status == ConstraintStatus.warn;

  factory ConstraintResult.pass(
    ConstraintKind kind,
    String title,
    String detail,
  ) =>
      ConstraintResult(
        kind: kind,
        status: ConstraintStatus.pass,
        title: title,
        detail: detail,
      );

  factory ConstraintResult.warn(
    ConstraintKind kind,
    String title,
    String detail,
  ) =>
      ConstraintResult(
        kind: kind,
        status: ConstraintStatus.warn,
        title: title,
        detail: detail,
      );

  factory ConstraintResult.fail(
    ConstraintKind kind,
    String title,
    String detail,
  ) =>
      ConstraintResult(
        kind: kind,
        status: ConstraintStatus.fail,
        title: title,
        detail: detail,
      );
}


/// A scored, context-resolved recommendation.
///
/// Produced by combining [Place] + [Experience] + [DiscoveryContext] +
/// [WeatherSnapshot] + travel estimates. This is the single object the UI
/// renders, so the ranking logic stays entirely out of the widget layer.
@immutable
class Recommendation {
  const Recommendation({
    required this.experience,
    required this.place,
    required this.tier,
    required this.constraints,
    required this.outboundTravel,
    required this.returnTravel,
    required this.score,
    required this.rank,
    required this.whyFits,
    required this.whyRanked,
    required this.matchReasons,
    required this.completableMinutes,
  });

  final Experience experience;
  final Place place;
  final FeasibilityTier tier;

  /// Full, ordered constraint evaluation. Drives all explanatory UI.
  final List<ConstraintResult> constraints;

  final TravelEstimate outboundTravel;
  final TravelEstimate returnTravel;

  /// 0–100 relevance score used purely for ordering.
  final double score;
  final int rank;

  final List<String> whyFits;
  final String whyRanked;

  /// Short, scannable tags shown on the card ("9 min away", "Indoor").
  final List<String> matchReasons;

  /// Total door-to-door time if the user does the full activity.
  final int completableMinutes;

  int get travelMinutes => outboundTravel.minutes + returnTravel.minutes;

  /// A shortened visit that still fits, or null when even the minimum does not.
  int? get trimmableMinutes {
    if (tier != FeasibilityTier.partial) return null;
    final fixed = travelMinutes + experience.minimumMinutes;
    return fixed > 0 ? fixed : null;
  }

  List<ConstraintResult> get blockers =>
      constraints.where((c) => c.isBlocking).toList();

  List<ConstraintResult> get caveats =>
      constraints.where((c) => c.isCaveat).toList();

  /// Headline reason shown when the card cannot be completed.
  String get primaryBlocker {
    if (blockers.isEmpty) return '';
    return blockers.first.detail;
  }

  String get categoryLabel => experience.category.label;

  String get priceLabel => experience.priceLabel;

  String get activityLabel => '${experience.activityMinutes} min';

  String get travelLabel => '${outboundTravel.minutes} min';

  /// The single-line verdict rendered in the feasibility banner.
  String get verdict {
    return switch (tier) {
      FeasibilityTier.feasible =>
        'Fits your ${DiscoveryContext.formatMinutes(completableMinutes)} door-to-door',
      FeasibilityTier.partial =>
        'Needs a trim — ${blockers.isEmpty ? caveats.first.detail : primaryBlocker}',
      FeasibilityTier.notFeasible => primaryBlocker,
    };
  }

  bool get canAddToPlan => tier != FeasibilityTier.notFeasible;

  /// A trimmed variant that fits the remaining window, for partial results.
  Recommendation? asTrimmed(int availableMinutes) {
    if (tier != FeasibilityTier.partial) return this;
    final fixed = travelMinutes + experience.minimumMinutes;
    if (fixed > availableMinutes) return null;
    return Recommendation(
      experience: experience,
      place: place,
      tier: FeasibilityTier.feasible,
      constraints: [
        for (final c in constraints)
          if (c.isBlocking)
            ConstraintResult.pass(
              c.kind,
              c.title,
              'Trimmed to the ${experience.minimumMinutes}-minute essential '
                  'version',
            )
          else
            c,
      ],
      outboundTravel: outboundTravel,
      returnTravel: returnTravel,
      score: score + 4,
      rank: rank,
      whyFits: whyFits,
      whyRanked: whyRanked,
      matchReasons: matchReasons,
      completableMinutes: fixed,
    );
  }
}

/// A saved place/experience pair, with when and why it was saved.
@immutable
class SavedExperience {
  const SavedExperience({
    required this.id,
    required this.experienceId,
    required this.placeId,
    required this.savedAt,
    this.collection,
    this.note,
  });

  final String id;
  final String experienceId;
  final String placeId;
  final DateTime savedAt;
  final String? collection;
  final String? note;

  factory SavedExperience.fromJson(Map<String, dynamic> json) {
    return SavedExperience(
      id: json.string('id') ?? '',
      experienceId: json.string('experienceId') ?? '',
      placeId: json.string('placeId') ?? '',
      savedAt:
          DateTime.tryParse(json.stringOrNull('savedAt') ?? '') ?? DateTime.now(),
      collection: json.stringOrNull('collection'),
      note: json.stringOrNull('note'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'experience_id': experienceId,
        'place_id': placeId,
        'saved_at': savedAt.toIso8601String(),
        'collection': collection,
        'note': note,
      };
}
