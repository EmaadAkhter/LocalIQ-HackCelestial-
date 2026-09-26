import 'chat_message.dart';

/// Contract for the AI travel assistant.
///
/// The local implementation resolves intent against the *current* discovery
/// context and recommendation set rather than generating text freely, which
/// is what keeps the assistant consistent with the rest of the product.
/// Swapping in an LLM-backed implementation only changes the body.
abstract interface class AssistantService {
  /// Streams (or returns) the assistant's reply for a user turn.
  Stream<ChatMessage> send({
    required ChatThread thread,
    required String prompt,
    required AssistantContext context,
  });

  /// Opening message for a fresh thread, seeded from the active context.
  Future<ChatMessage> greeting(AssistantContext context);

  /// Intent shortcuts rendered as chips under the composer.
  List<String> starters(AssistantContext context);
}

/// Everything the assistant is allowed to reason about. Passing this instead
/// of reaching into global state keeps the service pure and testable.
class AssistantContext {
  const AssistantContext({
    required this.locationLabel,
    required this.timeBudgetMinutes,
    required this.budget,
    required this.interests,
    required this.weatherNote,
    required this.weatherLabel,
    required this.feasibleCount,
    required this.partialCount,
    required this.blockedCount,
    required this.planStopCount,
    required this.planCost,
    required this.planLabel,
    this.availableRecommendationIds = const [],
  });

  final String locationLabel;
  final int timeBudgetMinutes;
  final int budget;
  final List<String> interests;
  final String weatherNote;
  final String weatherLabel;
  final int feasibleCount;
  final int partialCount;
  final int blockedCount;
  final int planStopCount;
  final int planCost;
  final String planLabel;

  /// Ids the assistant may attach to a reply. Prevents the model inventing
  /// places that are not in the current ranking.
  final List<String> availableRecommendationIds;
}
