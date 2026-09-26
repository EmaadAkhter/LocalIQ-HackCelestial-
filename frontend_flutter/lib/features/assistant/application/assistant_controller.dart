import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../context/application/discovery_context_controller.dart';
import '../../context/domain/discovery_context.dart';
import '../../../core/providers.dart';
import '../../itinerary/application/itinerary_controller.dart';
import '../../recommendations/application/recommendation_controller.dart';
import '../../recommendations/domain/recommendation.dart';
import '../domain/assistant_service.dart';
import '../domain/chat_message.dart';

/// Assistant conversation state. Streams replies and resolves the
/// recommendation cards each turn references.
class AssistantController extends Notifier<ChatThread> {
  StreamSubscription<ChatMessage>? _subscription;

  @override
  ChatThread build() {
    ref.onDispose(() => _subscription?.cancel());
    return ChatThread(
      id: 'thread-local',
      title: 'Local discovery',
      messages: const [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Builds the opening message from the live context.
  Future<void> initialise() async {
    if (state.messages.isNotEmpty) return;
    final service = ref.read(assistantServiceProvider);
    final greeting = await service.greeting(_context());
    state = state.copyWith(messages: [greeting]);
  }

  Future<void> send(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty) return;
    final service = ref.read(assistantServiceProvider);

    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(
          id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
          role: ChatRole.user,
          text: text,
          createdAt: DateTime.now(),
        ),
        ChatMessage(
          id: 'msg-pending-${DateTime.now().microsecondsSinceEpoch}',
          role: ChatRole.assistant,
          text: '',
          createdAt: DateTime.now(),
          isStreaming: true,
        ),
      ],
    );

    await _subscription?.cancel();
    _subscription = service
        .send(thread: state, prompt: text, context: _context())
        .listen((update) {
      _replaceLast(update);
    });
  }

  void _replaceLast(ChatMessage update) {
    final messages = [...state.messages];
    if (messages.isEmpty) return;
    messages[messages.length - 1] = update;
    state = state.copyWith(messages: messages);
  }

  /// Quick prompts derived from the current context.
  List<String> get starters {
    return ref.read(assistantServiceProvider).starters(_context());
  }

  void reset() {
    state = ChatThread(
      id: 'thread-local',
      title: 'Local discovery',
      messages: const [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Snapshots everything the assistant is allowed to reason about.
  AssistantContext _context() {
    final discovery = ref.read(discoveryContextProvider);
    final live = ref.read(liveContextProvider).value;
    final counts = ref.read(recommendationCountsProvider);
    final itinerary = ref.read(itineraryControllerProvider).value;
    final available = ref.read(assistantAllowedIdsProvider);

    return AssistantContext(
      locationLabel: discovery.locationLabel,
      timeBudgetMinutes: discovery.timeBudgetMinutes,
      budget: discovery.budget,
      interests: discovery.interests.map((i) => i.label).toList(),
      weatherNote: live?.weather.planningNote ?? 'Live conditions loading.',
      weatherLabel: live?.weather.summary ?? '—',
      feasibleCount: counts.feasible,
      partialCount: counts.partial,
      blockedCount: counts.blocked,
      planStopCount: itinerary?.stopCount ?? 0,
      planCost: itinerary?.totalCost ?? 0,
      planLabel: _planLabel(itinerary, discovery),
      availableRecommendationIds: available,
    );
  }

  static String _planLabel(Object? itinerary, DiscoveryContext context) {
    if (itinerary == null) return 'No plan yet.';
    // Uses the public getters available on Itinerary without importing it here.
    final dynamic value = itinerary;
    if (value.stopCount == 0) return 'Your plan is empty.';
    return 'Plan: ${value.stopCount} stops · ${value.costLabel} · '
        '${value.totalLabel} against your ${context.timeLabel}.';
  }
}

final assistantControllerProvider =
    NotifierProvider<AssistantController, ChatThread>(
  AssistantController.new,
  name: 'localiq.assistant',
);

/// Ids the assistant may attach to a reply. Constrained to the current
/// ranking so it can never cite a place that is not live.
final assistantAllowedIdsProvider = Provider<List<String>>((ref) {
  final result = ref.watch(recommendationControllerProvider).value;
  if (result == null) return const [];
  return [
    for (final r in [...result.feasible, ...result.partial])
      r.experience.id,
  ];
});

/// Read-only alias used by the profile screen's activity counters.
final assistantThreadProvider = assistantControllerProvider;

/// Resolves a message's card references against the live ranking.
final messageRecommendationsProvider =
    Provider.family<List<Recommendation>, List<String>>((ref, ids) {
  final result = ref.watch(recommendationControllerProvider).value;
  if (result == null) return const [];
  final out = <Recommendation>[];
  for (final id in ids) {
    final match = result.byId(id);
    if (match != null) out.add(match);
  }
  return out;
});
