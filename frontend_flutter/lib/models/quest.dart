import 'package:flutter/material.dart';

/// A Quest — a curated multi-stop local experience path.
@immutable
class Quest {
  const Quest({
    required this.id,
    required this.title,
    required this.description,
    required this.coverImageUrl,
    required this.stops,
    required this.totalMinutes,
    required this.estimatedCostInr,
    required this.difficulty,
    required this.tags,
    this.reward,
    this.isWeatherSensitive = false,
    this.bestTimeLabel = 'Any time',
  });

  final String id;
  final String title;
  final String description;
  final String coverImageUrl;
  final List<QuestStop> stops;
  final int totalMinutes;
  final int estimatedCostInr;
  final QuestDifficulty difficulty;
  final List<String> tags;
  final QuestReward? reward;
  final bool isWeatherSensitive;
  final String bestTimeLabel;

  int get stopCount => stops.length;
  String get costLabel => estimatedCostInr == 0 ? 'Free' : '₹$estimatedCostInr';
  String get durationLabel {
    if (totalMinutes < 60) return '$totalMinutes min';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

@immutable
class QuestStop {
  const QuestStop({
    required this.stopNumber,
    required this.placeId,
    required this.placeName,
    required this.task,
    required this.activityMinutes,
    this.imageUrl,
    this.tip,
  });

  final int stopNumber;
  final String placeId;
  final String placeName;
  final String task;
  final int activityMinutes;
  final String? imageUrl;
  final String? tip;
}

enum QuestDifficulty { easy, moderate, energetic }

extension QuestDifficultyX on QuestDifficulty {
  String get label => switch (this) {
        QuestDifficulty.easy => 'Easy',
        QuestDifficulty.moderate => 'Moderate',
        QuestDifficulty.energetic => 'Energetic',
      };
  Color get color => switch (this) {
        QuestDifficulty.easy => const Color(0xFF0E7C5A),
        QuestDifficulty.moderate => const Color(0xFFB07514),
        QuestDifficulty.energetic => const Color(0xFFC93B3B),
      };
}

@immutable
class QuestReward {
  const QuestReward({
    required this.xpPoints,
    required this.badgeId,
    required this.badgeLabel,
  });

  final int xpPoints;
  final String badgeId;
  final String badgeLabel;
}

/// User progress on a quest (current stop index, started, completed).
@immutable
class UserQuestProgress {
  const UserQuestProgress({
    required this.questId,
    required this.currentStopIndex,
    required this.startedAt,
    this.completedAt,
    this.stopsCompleted = const [],
  });

  final String questId;
  final int currentStopIndex;
  final DateTime startedAt;
  final DateTime? completedAt;
  final List<int> stopsCompleted;

  bool get isCompleted => completedAt != null;
}

/// A badge earned through quests or milestones.
@immutable
class ExperienceBadge {
  const ExperienceBadge({
    required this.id,
    required this.label,
    required this.description,
    required this.iconEmoji,
    required this.earnedAt,
    this.category = BadgeCategory.general,
  });

  final String id;
  final String label;
  final String description;
  final String iconEmoji;
  final DateTime earnedAt;
  final BadgeCategory category;
}

enum BadgeCategory { general, foodie, explorer, cultural, adventurer, social }
