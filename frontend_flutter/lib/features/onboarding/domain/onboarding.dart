import '../../../core/utils/json_map_x.dart';

/// One turn of the guided taste conversation.
class OnboardingStep {
  const OnboardingStep({
    this.sessionId,
    this.status = 'in_progress',
    this.step = 0,
    this.totalSteps = 0,
    this.progress = 0,
    this.ack,
    this.prompt,
    this.options = const [],
    this.multi = false,
    this.freeText = false,
    this.done = false,
    this.completed = false,
    this.taste,
  });

  final int? sessionId;
  final String status;
  final int step;
  final int totalSteps;
  final double progress;

  /// The host's reaction to the previous answer ("Excellent taste.").
  final String? ack;
  final String? prompt;
  final List<String> options;
  final bool multi;
  final bool freeText;
  final bool done;
  final bool completed;
  final TasteSnapshot? taste;

  factory OnboardingStep.fromJson(Map<String, dynamic> json) {
    final taste = json.pick('taste');
    return OnboardingStep(
      sessionId: json.intOrNull('sessionId'),
      status: json.string('status') ?? 'in_progress',
      step: json.intValue('step'),
      totalSteps: json.intValue('totalSteps'),
      progress: json.doubleValue('progress'),
      ack: json.stringOrNull('ack'),
      prompt: json.stringOrNull('prompt'),
      options: json.stringList('options'),
      multi: json.boolValue('multi'),
      freeText: json.boolValue('freeText'),
      done: json.boolValue('done'),
      completed: json.boolValue('completed'),
      taste: taste is Map
          ? TasteSnapshot.fromJson(taste.cast<String, dynamic>())
          : null,
    );
  }
}

/// The taste vector distilled from the conversation.
class TasteSnapshot {
  const TasteSnapshot({
    this.likes = const [],
    this.dislikes = const [],
    this.text = '',
    this.vector = const {},
  });

  final List<String> likes;
  final List<String> dislikes;
  final String text;
  final Map<String, double> vector;

  int get tagCount => vector.length;

  factory TasteSnapshot.fromJson(Map<String, dynamic> json) {
    final rawVector = json.pick('vector');
    final vector = <String, double>{};
    if (rawVector is Map) {
      rawVector.forEach((key, value) {
        if (value is num) vector['$key'] = value.toDouble();
      });
    }
    return TasteSnapshot(
      likes: json.stringList('likes'),
      dislikes: json.stringList('dislikes'),
      text: json.string('text') ?? '',
      vector: vector,
    );
  }
}
