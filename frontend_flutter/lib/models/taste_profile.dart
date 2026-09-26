import 'package:flutter/material.dart';

/// A user's discovered taste and preference profile.
///
/// Drives personalized recommendations. Always visible and editable.
@immutable
class TasteProfile {
  const TasteProfile({
    this.naturallanguageSummary = '',
    this.preferredVibes = const [],
    this.preferredCategories = const [],
    this.preferredTimeOfDay = PreferredTime.anytime,
    this.crowdTolerance = CrowdTolerance.moderate,
    this.budgetTendency = BudgetTendency.moderate,
    this.groupSizePreference = GroupSizePreference.solo,
    this.indoorOutdoor = IndoorOutdoor.both,
    this.isPaused = false,
    this.lastUpdated,
  });

  /// Natural language summary of the user's preferences.
  /// Example: "Prefers quiet cultural experiences, coffee, photography and hidden gems."
  final String naturallanguageSummary;

  final List<String> preferredVibes;
  final List<String> preferredCategories;
  final PreferredTime preferredTimeOfDay;
  final CrowdTolerance crowdTolerance;
  final BudgetTendency budgetTendency;
  final GroupSizePreference groupSizePreference;
  final IndoorOutdoor indoorOutdoor;

  /// When true, personalization is paused for the current session.
  final bool isPaused;
  final DateTime? lastUpdated;

  TasteProfile copyWith({
    String? naturallanguageSummary,
    List<String>? preferredVibes,
    List<String>? preferredCategories,
    PreferredTime? preferredTimeOfDay,
    CrowdTolerance? crowdTolerance,
    BudgetTendency? budgetTendency,
    GroupSizePreference? groupSizePreference,
    IndoorOutdoor? indoorOutdoor,
    bool? isPaused,
    DateTime? lastUpdated,
  }) {
    return TasteProfile(
      naturallanguageSummary: naturallanguageSummary ?? this.naturallanguageSummary,
      preferredVibes: preferredVibes ?? this.preferredVibes,
      preferredCategories: preferredCategories ?? this.preferredCategories,
      preferredTimeOfDay: preferredTimeOfDay ?? this.preferredTimeOfDay,
      crowdTolerance: crowdTolerance ?? this.crowdTolerance,
      budgetTendency: budgetTendency ?? this.budgetTendency,
      groupSizePreference: groupSizePreference ?? this.groupSizePreference,
      indoorOutdoor: indoorOutdoor ?? this.indoorOutdoor,
      isPaused: isPaused ?? this.isPaused,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  static TasteProfile get defaultProfile => const TasteProfile(
        naturallanguageSummary:
            'Building your taste profile as you explore more.',
        preferredVibes: ['Cultural', 'Relaxed'],
        preferredCategories: ['Food', 'Art'],
        preferredTimeOfDay: PreferredTime.anytime,
        crowdTolerance: CrowdTolerance.moderate,
        budgetTendency: BudgetTendency.moderate,
      );
}

enum PreferredTime { morning, afternoon, evening, night, anytime }

extension PreferredTimeX on PreferredTime {
  String get label => switch (this) {
        PreferredTime.morning => 'Morning',
        PreferredTime.afternoon => 'Afternoon',
        PreferredTime.evening => 'Evening',
        PreferredTime.night => 'Night',
        PreferredTime.anytime => 'Anytime',
      };
  IconData get icon => switch (this) {
        PreferredTime.morning => Icons.wb_sunny_outlined,
        PreferredTime.afternoon => Icons.light_mode_outlined,
        PreferredTime.evening => Icons.wb_twilight_outlined,
        PreferredTime.night => Icons.nightlight_outlined,
        PreferredTime.anytime => Icons.schedule_outlined,
      };
}

enum CrowdTolerance { quiet, moderate, busy, dontMind }

extension CrowdToleranceX on CrowdTolerance {
  String get label => switch (this) {
        CrowdTolerance.quiet => 'Prefer quiet',
        CrowdTolerance.moderate => 'Some crowd ok',
        CrowdTolerance.busy => 'Love the buzz',
        CrowdTolerance.dontMind => "Don't mind",
      };
}

enum BudgetTendency { budget, moderate, comfortable, splurge }

extension BudgetTendencyX on BudgetTendency {
  String get label => switch (this) {
        BudgetTendency.budget => 'Budget-conscious',
        BudgetTendency.moderate => 'Moderate spender',
        BudgetTendency.comfortable => 'Comfortable',
        BudgetTendency.splurge => 'Splurge-friendly',
      };
}

enum GroupSizePreference { solo, couple, smallGroup, largeGroup }

extension GroupSizePreferenceX on GroupSizePreference {
  String get label => switch (this) {
        GroupSizePreference.solo => 'Solo',
        GroupSizePreference.couple => 'Couple',
        GroupSizePreference.smallGroup => 'Small group (3–6)',
        GroupSizePreference.largeGroup => 'Large group (7+)',
      };
}

enum IndoorOutdoor { indoor, outdoor, both }

extension IndoorOutdoorX on IndoorOutdoor {
  String get label => switch (this) {
        IndoorOutdoor.indoor => 'Indoor',
        IndoorOutdoor.outdoor => 'Outdoor',
        IndoorOutdoor.both => 'Both',
      };
}
