import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/quest.dart';

/// The state of one active quest session.
class ActiveQuestState {
  const ActiveQuestState({
    required this.quest,
    required this.progress,
  });

  final Quest quest;
  final UserQuestProgress progress;

  /// 0-based current stop index.
  int get currentStopIndex => progress.currentStopIndex;
  int get totalStops => quest.stops.length;
  bool get isCompleted => progress.isCompleted;
  bool get isOnLastStop => currentStopIndex >= totalStops - 1;

  QuestStop get currentStop => quest.stops[currentStopIndex];

  QuestStop? get nextStop {
    final next = currentStopIndex + 1;
    if (next < quest.stops.length) return quest.stops[next];
    return null;
  }

  ActiveQuestState copyWith({UserQuestProgress? progress}) {
    return ActiveQuestState(
      quest: quest,
      progress: progress ?? this.progress,
    );
  }
}

/// Manages a map of questId → ActiveQuestState.
/// Stores started, in-progress, and completed quests.
class QuestSessionState {
  const QuestSessionState({
    this.sessions = const {},
    this.earnedBadges = const [],
    this.totalXp = 0,
  });

  final Map<String, ActiveQuestState> sessions;
  final List<ExperienceBadge> earnedBadges;
  final int totalXp;

  bool isStarted(String questId) => sessions.containsKey(questId);
  bool isCompleted(String questId) =>
      sessions[questId]?.isCompleted ?? false;
  ActiveQuestState? getSession(String questId) => sessions[questId];

  QuestSessionState copyWith({
    Map<String, ActiveQuestState>? sessions,
    List<ExperienceBadge>? earnedBadges,
    int? totalXp,
  }) {
    return QuestSessionState(
      sessions: sessions ?? this.sessions,
      earnedBadges: earnedBadges ?? this.earnedBadges,
      totalXp: totalXp ?? this.totalXp,
    );
  }
}

class QuestController extends Notifier<QuestSessionState> {
  @override
  QuestSessionState build() => const QuestSessionState();

  /// Start a new quest, or resume if already started.
  void startQuest(Quest quest) {
    final existing = state.sessions[quest.id];
    if (existing != null && !existing.isCompleted) return; // already in progress

    final progress = UserQuestProgress(
      questId: quest.id,
      currentStopIndex: 0,
      startedAt: DateTime.now(),
      stopsCompleted: const [],
    );

    final newSessions = Map<String, ActiveQuestState>.from(state.sessions);
    newSessions[quest.id] = ActiveQuestState(quest: quest, progress: progress);

    state = state.copyWith(sessions: newSessions);
  }

  /// Mark the current stop as complete and advance to next (or complete quest).
  /// Returns true if the quest was completed.
  bool completeCurrentStop(String questId) {
    final session = state.sessions[questId];
    if (session == null || session.isCompleted) return false;

    final stopsCompleted = [
      ...session.progress.stopsCompleted,
      session.progress.currentStopIndex,
    ];

    final nextIndex = session.progress.currentStopIndex + 1;
    final isLastStop = nextIndex >= session.quest.stops.length;

    final updatedProgress = UserQuestProgress(
      questId: questId,
      currentStopIndex: isLastStop ? session.progress.currentStopIndex : nextIndex,
      startedAt: session.progress.startedAt,
      completedAt: isLastStop ? DateTime.now() : null,
      stopsCompleted: stopsCompleted,
    );

    final newSessions = Map<String, ActiveQuestState>.from(state.sessions);
    newSessions[questId] = session.copyWith(progress: updatedProgress);

    final newXp = isLastStop
        ? state.totalXp + (session.quest.reward?.xpPoints ?? 0)
        : state.totalXp;

    final newBadges = isLastStop && session.quest.reward != null
        ? [
            ...state.earnedBadges,
            ExperienceBadge(
              id: session.quest.reward!.badgeId,
              label: session.quest.reward!.badgeLabel,
              description: 'Earned by completing: ${session.quest.title}',
              iconEmoji: '🏆',
              earnedAt: DateTime.now(),
              category: BadgeCategory.explorer,
            ),
          ]
        : state.earnedBadges;

    state = state.copyWith(
      sessions: newSessions,
      totalXp: newXp,
      earnedBadges: newBadges,
    );

    return isLastStop;
  }

  /// Abandon / reset a quest session.
  void abandonQuest(String questId) {
    final newSessions = Map<String, ActiveQuestState>.from(state.sessions)
      ..remove(questId);
    state = state.copyWith(sessions: newSessions);
  }
}

final questControllerProvider =
    NotifierProvider<QuestController, QuestSessionState>(
  QuestController.new,
  name: 'localiq.questController',
);

/// Convenience: total completed quests count.
final completedQuestCountProvider = Provider<int>((ref) {
  final state = ref.watch(questControllerProvider);
  return state.sessions.values.where((s) => s.isCompleted).length;
}, name: 'localiq.completedQuestCount');
