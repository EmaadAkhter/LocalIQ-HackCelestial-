import '../domain/onboarding.dart';
import '../domain/onboarding_repository.dart';

/// Offline [OnboardingRepository]: a short, universal taste conversation that
/// works for any city and any user — not anchored to Mumbai or food.
///
/// The questions surface:
///   • Whether the user is a traveller or a local
///   • Who they are exploring with
///   • What *genres* of experience excite them most (culture, outdoors, food,
///     nightlife, wellness, etc.)
///   • Their energy level / pace preference
///   • Budget orientation
///   • Anything they want to avoid
///   • A free-text notes step
class LocalOnboardingRepository implements OnboardingRepository {
  static const _steps = <_Step>[
    _Step(
      key: 'familiarity',
      prompt:
          "Welcome — I'm your LocalIQ curator. Are you discovering this city for the first time, or do you already know it well?",
      ack: 'Noted.',
      options: [
        _Option('First-time visitor', {}),
        _Option('Know it a little', {'local': 0.3}),
        _Option('I live here', {'local_favorite': 0.6, 'hidden_gem': 0.6}),
      ],
    ),
    _Step(
      key: 'company',
      prompt: 'Who are you exploring with today?',
      ack: 'Perfect.',
      options: [
        _Option('Just me', {'solo_friendly': 1.0, 'quiet_retreat': 0.4}),
        _Option('Partner / date', {'couple_friendly': 1.0, 'romantic': 1.0}),
        _Option('Friends', {'group_friendly': 1.0, 'social': 0.5}),
        _Option('Family with kids', {'family_friendly': 1.0, 'child_friendly': 0.8}),
      ],
    ),
    _Step(
      key: 'genres',
      prompt:
          'What kinds of experiences fire you up? Pick everything that calls to you.',
      ack: 'Great taste.',
      multi: true,
      options: [
        _Option('Food & drink', {'food': 1.2, 'street_food': 0.8, 'cafe': 0.7}),
        _Option('Art & culture', {'cultural': 1.2, 'museum': 1.0, 'heritage': 0.9}),
        _Option('Outdoor & nature', {'outdoor': 1.2, 'nature': 1.0, 'parks': 0.8}),
        _Option('Nightlife & music', {'nightlife': 1.2, 'music': 1.0, 'bars': 0.8}),
        _Option('Shopping & markets', {'shopping': 1.2, 'markets': 1.0}),
        _Option('Wellness & spa', {'wellness': 1.2, 'spa': 1.0, 'yoga': 0.7}),
        _Option('Spiritual & heritage', {'spiritual': 1.2, 'temple': 1.0, 'heritage': 0.9}),
        _Option('Adventure & sport', {'adventure': 1.2, 'sport': 1.0, 'active': 0.8}),
      ],
    ),
    _Step(
      key: 'vibe',
      prompt:
          'How do you like to move through a place — slow and immersive, or brisk and packed?',
      ack: 'Understood.',
      options: [
        _Option('Slow & immersive', {'chill': 1.0, 'quiet_retreat': 0.6}),
        _Option('Quick highlights tour', {'energetic': 0.8, 'quick': 1.0}),
        _Option('One unmissable spot', {'curated': 1.0, 'quiet_retreat': 0.4}),
        _Option('Spontaneous, surprise me', {'hidden_gem': 0.8, 'off_beaten_path': 1.0}),
      ],
    ),
    _Step(
      key: 'budget',
      prompt: 'What is your budget comfort zone for activities and dining?',
      ack: 'Got it.',
      options: [
        _Option('Free or very cheap', {'free': 1.2, 'budget': 1.0}),
        _Option('Mid-range is fine', {'mid_range': 1.0}),
        _Option('Happy to splurge', {'premium': 1.2, 'luxury': 0.8}),
        _Option('Depends on the experience', {}),
      ],
    ),
    _Step(
      key: 'avoid',
      prompt:
          "Is there anything I should keep off your list? Allergies, types of places you dislike, anything at all — I'll keep it away.",
      ack: "I'll keep that off your list.",
      freeText: true,
      negative: true,
    ),
    _Step(
      key: 'notes',
      prompt:
          "Last one — anything else worth knowing about you? Even one word helps me curate better. Then your first picks will be ready.",
      ack: 'Perfect.',
      freeText: true,
    ),
  ];

  int? _sessionId;
  int _cursor = 0;
  bool _completed = false;
  final Map<String, double> _vector = {};
  final List<String> _transcript = [];

  @override
  Future<OnboardingStep> start({bool restart = false}) async {
    if (restart) {
      _cursor = 0;
      _completed = false;
      _vector.clear();
      _transcript.clear();
      _sessionId = null;
    }
    _sessionId ??= 1;
    return _current();
  }

  @override
  Future<OnboardingStep> status() async {
    if (_sessionId == null) {
      return const OnboardingStep(status: 'not_started', totalSteps: 7);
    }
    return _current();
  }

  @override
  Future<OnboardingStep> answer(
    int sessionId, {
    String? message,
    List<String> selections = const [],
  }) async {
    if (_cursor >= _steps.length) return _current();
    final step = _steps[_cursor];
    final chosen = selections.map((s) => s.trim().toLowerCase()).toSet();
    for (final option in step.options) {
      if (chosen.contains(option.label.toLowerCase())) {
        option.tags.forEach((tag, weight) {
          _vector[tag] = (_vector[tag] ?? 0) + weight;
        });
      }
    }
    final text = (message ?? '').trim();
    if (text.isNotEmpty) _transcript.add(text);
    // Simple offline signal: words become light tags, negatives on the avoid step.
    if (text.isNotEmpty && (step.freeText || step.options.isEmpty)) {
      final sign = step.negative ? -1.0 : 1.0;
      for (final word in text.toLowerCase().split(RegExp(r'[^a-z]+'))) {
        if (word.length < 4) continue;
        _vector[word] = (_vector[word] ?? 0) + sign * 0.5;
      }
    }
    _cursor = (_cursor + 1).clamp(0, _steps.length);
    if (_cursor >= _steps.length) _completed = true;
    return _current();
  }

  OnboardingStep _current() {
    final done = _cursor >= _steps.length;
    return OnboardingStep(
      sessionId: _sessionId,
      status: done ? 'completed' : 'in_progress',
      step: _cursor.clamp(0, _steps.length),
      totalSteps: _steps.length,
      progress: (_cursor.clamp(0, _steps.length)) / _steps.length,
      ack: _cursor == 0 ? null : _steps[_cursor - 1 < 0 ? 0 : _cursor - 1].ack,
      prompt: done ? null : _steps[_cursor].prompt,
      options: done ? const [] : [for (final o in _steps[_cursor].options) o.label],
      multi: !done && _steps[_cursor].multi,
      freeText: !done && _steps[_cursor].freeText,
      done: done,
      completed: _completed,
      taste: done ? _snapshot() : null,
    );
  }

  TasteSnapshot _snapshot() {
    final likes = <String>[];
    final dislikes = <String>[];
    final sorted = _vector.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    for (final entry in sorted.take(12)) {
      if (entry.value >= 0) {
        likes.add(entry.key);
      } else {
        dislikes.add(entry.key);
      }
    }
    return TasteSnapshot(
      likes: likes,
      dislikes: dislikes,
      text: likes.isEmpty
          ? 'Tell me more and I will sharpen your recommendations.'
          : 'You lean toward ${likes.take(4).join(', ')}.',
      vector: Map.of(_vector),
    );
  }
}

class _Step {
  const _Step({
    required this.key,
    required this.prompt,
    this.ack,
    this.options = const [],
    this.multi = false,
    this.freeText = false,
    this.negative = false,
  });

  final String key;
  final String prompt;
  final String? ack;
  final List<_Option> options;
  final bool multi;
  final bool freeText;
  final bool negative;
}

class _Option {
  const _Option(this.label, this.tags);
  final String label;
  final Map<String, double> tags;
}
