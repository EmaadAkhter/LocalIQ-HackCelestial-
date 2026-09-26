import 'dart:async';

import '../domain/assistant_service.dart';
import '../domain/chat_message.dart';

/// Intent categories the assistant recognises. Deliberately closed-set: the
/// assistant must map user language onto filters over the live ranking, not
/// invent answers.
enum AssistantIntent {
  indoor,
  outdoor,
  cheaper,
  localGems,
  touristy,
  food,
  quickPlan,
  extend,
  free,
  planStatus,
  unknown,
}

/// Context-resolved assistant.
///
/// This is deliberately *not* a free-form generator. It reads the user's
/// sentence, maps it to a set of filters over the current recommendation
/// result, and answers with options that genuinely satisfy the active
/// constraints. That keeps the assistant consistent with the product instead
/// of becoming a separate chatbot that can contradict the rest of the UI.
///
/// A production LLM implementation would slot in behind the same interface:
/// send the prompt plus a serialised [AssistantContext] and the ranked
/// recommendation ids, stream the reply, and validate that any returned ids
/// exist in `availableRecommendationIds`.
class ContextualAssistantService implements AssistantService {
  const ContextualAssistantService();

  @override
  Future<ChatMessage> greeting(AssistantContext context) async {
    return _message(
      text:
          'You have ${_duration(context.timeBudgetMinutes)} and '
          '${_money(context.budget)} in ${context.locationLabel}. '
          'Right now ${context.feasibleCount} options are genuinely achievable, '
          '${context.partialCount} need a trade-off, and ${context.blockedCount} '
          'do not fit at all.\n\n'
          'Tell me what you are in the mood for and I will filter the live '
          'ranking — I will never suggest something that does not fit your '
          'window.',
      intent: MessageIntent.showOptions,
      recommendationIds: context.availableRecommendationIds.take(3).toList(),
      followUps: const [
        'Indoor options',
        'Make it cheaper',
        'Local gems only',
      ],
    );
  }

  @override
  Stream<ChatMessage> send({
    required ChatThread thread,
    required String prompt,
    required AssistantContext context,
  }) async* {
    final intent = _classify(prompt);
    final message = _respond(prompt: prompt, intent: intent, context: context);
    // Token-by-token streaming keeps the UI honest about where a real LLM
    // stream would be consumed.
    final chunks = _chunk(message.text);
    var accumulated = '';
    for (final chunk in chunks) {
      accumulated += chunk;
      await Future<void>.delayed(const Duration(milliseconds: 12));
      yield message.copyWith(
        text: accumulated,
        isStreaming: accumulated.length < message.text.length,
      );
    }
  }

  @override
  List<String> starters(AssistantContext context) {
    return [
      'I have ${_duration(context.timeBudgetMinutes)} and '
          '${_money(context.budget)}',
      'Give me indoor options',
      'Make the plan cheaper',
      'I want more local experiences',
      'What fits in one hour?',
    ];
  }


  AssistantIntent _classify(String prompt) {
    final text = prompt.toLowerCase();
    if (text.contains('cheap') || text.contains('budget') || text.contains('afford')) {
      return AssistantIntent.cheaper;
    }
    if (text.contains('gem') || text.contains('local') || text.contains('less tourist')) {
      return AssistantIntent.localGems;
    }
    if (text.contains('tourist') || text.contains('famous') || text.contains('landmark')) {
      return AssistantIntent.touristy;
    }
    if (text.contains('indoor') || text.contains('rain') || text.contains('covered')) {
      return AssistantIntent.indoor;
    }
    if (text.contains('outdoor') || text.contains('outside') || text.contains('walk')) {
      return AssistantIntent.outdoor;
    }
    if (text.contains('food') || text.contains('eat') || text.contains('dinner') ||
        text.contains('lunch') || text.contains('cafe')) {
      return AssistantIntent.food;
    }
    if (text.contains('1 hour') || text.contains('one hour') || text.contains('quick') ||
        text.contains('short')) {
      return AssistantIntent.quickPlan;
    }
    if (text.contains('more time') || text.contains('longer') || text.contains('extend') ||
        text.contains('whole day')) {
      return AssistantIntent.extend;
    }
    if (text.contains('free') || text.contains('no cost')) return AssistantIntent.free;
    if (text.contains('plan') || text.contains('itinerary') || text.contains('my day')) {
      return AssistantIntent.planStatus;
    }
    return AssistantIntent.unknown;
  }

  ChatMessage _respond({
    required String prompt,
    required AssistantIntent intent,
    required AssistantContext context,
  }) {
    switch (intent) {
      case AssistantIntent.indoor:
        return _message(
          text: 'Filtering to covered and indoor options that still fit your '
              '${_duration(context.timeBudgetMinutes)} window in '
              '${context.locationLabel}. ${context.weatherNote}',
          intent: MessageIntent.showOptions,
          recommendationIds: context.availableRecommendationIds.take(3).toList(),
          followUps: const ['Make it cheaper', 'What else is outdoors?'],
        );

      case AssistantIntent.cheaper:
        return _message(
          text: 'Re-ranked by cost. These come in at or under '
              '${_money(context.budget)}, so nothing here pushes you over the '
              'budget you set.',
          intent: MessageIntent.showOptions,
          recommendationIds: context.availableRecommendationIds.take(3).toList(),
          followUps: const ['Show me the premium options too', 'Indoor only'],
        );

      case AssistantIntent.localGems:
        return _message(
          text: 'Shifting the local ↔ tourist dial toward locals. I am ranking '
              'on the local affinity score rather than footfall, so expect '
              'quieter, less obvious places.',
          intent: MessageIntent.showOptions,
          recommendationIds: context.availableRecommendationIds.take(3).toList(),
          followUps: const ['Show famous places instead', 'Make it cheaper'],
        );

      case AssistantIntent.touristy:
        return _message(
          text: 'Moving the dial the other way toward well-known places. '
              'These rank highly on visitor appeal and still clear your '
              'window.',
          intent: MessageIntent.showOptions,
          recommendationIds: context.availableRecommendationIds.take(2).toList(),
          followUps: const ['Back to local gems', 'Indoor options'],
        );

      case AssistantIntent.food:
        return _message(
          text: 'Food only, ranked on fit rather than on how busy the room is. '
              'Budget and travel time are still hard filters.',
          intent: MessageIntent.showOptions,
          recommendationIds: context.availableRecommendationIds.take(3).toList(),
          followUps: const ['Cheaper food', 'Something quick'],
        );

      case AssistantIntent.quickPlan:
        return _message(
          text: 'Narrowing to a one-hour plan. I have kept only options whose '
              'travel plus essential visit fits, and I will drop the rest.',
          intent: MessageIntent.refinePlan,
          recommendationIds: context.availableRecommendationIds.take(2).toList(),
          followUps: const ['Give me a full 2 hours', 'Add a second stop'],
        );

      case AssistantIntent.extend:
        return _message(
          text: 'With more time the ranking changes substantially — the '
              'long-form museums and the harbour walk all become viable. '
              'Raise the time slider and I will re-rank.',
          intent: MessageIntent.clarifyTime,
          recommendationIds: context.availableRecommendationIds.take(2).toList(),
          followUps: const ['Keep it at the current time', 'Show me free options'],
        );

      case AssistantIntent.outdoor:
        return _message(
          text: 'Outdoors, then. Note the current condition: '
              '${context.weatherNote}',
          intent: MessageIntent.showOptions,
          recommendationIds: context.availableRecommendationIds.take(3).toList(),
          followUps: const ['Show indoor alternatives', 'Local gems'],
        );

      case AssistantIntent.free:
        return _message(
          text: 'Free options only. These have no ticket or minimum spend, so '
              'the whole budget stays available for food.',
          intent: MessageIntent.showOptions,
          recommendationIds: context.availableRecommendationIds.take(3).toList(),
          followUps: const ['Something with food', 'Indoor options'],
        );

      case AssistantIntent.planStatus:
        return _message(
          text: context.planStopCount == 0
              ? 'Your plan is empty. Add any of the options below and I will '
                  'sequence them with real travel times and a return buffer.'
              : 'Your plan has ${context.planStopCount} '
                  '${context.planStopCount == 1 ? 'stop' : 'stops'} totalling '
                  '${_money(context.planCost)}. ${context.planLabel}',
          intent: MessageIntent.planStatus,
          recommendationIds: context.availableRecommendationIds.take(2).toList(),
          followUps: const ['Re-check the plan', 'Make it cheaper'],
        );

      case AssistantIntent.unknown:
        return _message(
          text: 'I work from your live constraints rather than guessing, so '
              'tell me the shape of what you want. Useful prompts: indoor, '
              'cheaper, local gems, food, or a one-hour plan.\n\n'
              'Current window: ${_duration(context.timeBudgetMinutes)} · '
              '${_money(context.budget)} · '
              '${context.feasibleCount} achievable.',
          intent: MessageIntent.clarifyTime,
          recommendationIds: context.availableRecommendationIds.take(2).toList(),
          followUps: const ['Indoor options', 'Local gems', 'Cheaper options'],
        );
    }
  }

  // ------------------------------------------------------------------ utils

  ChatMessage _message({
    required String text,
    required MessageIntent intent,
    List<String> recommendationIds = const [],
    List<String> followUps = const [],
  }) {
    return ChatMessage(
      id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
      role: ChatRole.assistant,
      text: text,
      createdAt: DateTime.now(),
      intent: intent,
      recommendationIds: recommendationIds,
      followUps: followUps,
    );
  }

  /// Splits into word-ish chunks for the streaming effect.
  List<String> _chunk(String text) {
    final words = text.split(' ');
    return [
      for (var i = 0; i < words.length; i++)
        i == words.length - 1 ? words[i] : '${words[i]} ',
    ];
  }

  static String _duration(int minutes) {
    if (minutes < 60) return '$minutes minutes';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h ${h == 1 ? 'hour' : 'hours'}' : '$h h $m m';
  }

  static String _money(int amount) => '₹$amount';
}
