import '../domain/onboarding.dart';
import '../domain/onboarding_repository.dart';

/// Offline [OnboardingRepository]: the same seven-step conversation the backend
/// scripts, so the taste flow works (and is testable) without a server.
class LocalOnboardingRepository implements OnboardingRepository {
  static const _steps = <_Step>[
    _Step(
      key: 'familiarity',
      prompt:
          "Good evening — I'll be looking after you. Tell me, is this your first time in Mumbai, or do you know her already?",
      ack: 'Noted.',
      options: [
        _Option('First time', {}),
        _Option('I know her well', {'local_favorite': 0.6, 'hidden_gem': 0.6}),
        _Option('Somewhere in between', {'local': 0.3}),
      ],
    ),
    _Step(
      key: 'company',
      prompt: 'And who has the pleasure of your company this evening?',
      ack: 'A fine choice.',
      options: [
        _Option('Just me', {'solo_friendly': 1.0, 'quiet_retreat': 0.4}),
        _Option('Someone special', {'couple_friendly': 1.0, 'romantic': 1.0}),
        _Option('A few friends', {'group_friendly': 1.0, 'nightlife': 0.5}),
        _Option('Family', {'family_friendly': 1.0, 'child_friendly': 0.5}),
      ],
    ),
    _Step(
      key: 'palate',
      prompt:
          'Now the part I enjoy most. What should be on the table? Choose as many as tempt you.',
      ack: 'Excellent taste.',
      multi: true,
      options: [
        _Option('Street food', {'street_food': 1.2, 'good_for_street_food': 1.0}),
        _Option('Fine dining', {'good_for_fine_dining': 1.2, 'premium': 0.7}),
        _Option('Cocktails', {'cocktails': 1.2, 'bars': 0.8}),
        _Option('Coffee & desserts', {'cafe': 1.2, 'good_for_coffee': 1.0}),
        _Option('Seafood', {'seafood': 1.2}),
        _Option('Vegetarian', {'vegetarian': 1.2}),
        _Option('Sweets', {'snacks': 0.9}),
      ],
    ),
    _Step(
      key: 'pace',
      prompt:
          'How do you like to move through a city — lingering over a long table, or brisk and packed?',
      ack: 'Understood.',
      options: [
        _Option('Slow and lingering', {'chill': 1.0, 'quiet_retreat': 0.5}),
        _Option('Brisk and packed', {'energetic': 1.0}),
        _Option('One perfect stop', {'quiet_retreat': 0.6, 'chill': 0.6}),
      ],
    ),
    _Step(
      key: 'hour',
      prompt: 'And the hour that suits you best?',
      ack: 'Beautiful.',
      options: [
        _Option('Sunrise', {'sunrise': 1.2, 'sunrise_view': 1.0}),
        _Option('Golden hour', {'sunset': 1.2, 'sunset_view': 1.0}),
        _Option('After dark', {'nightlife': 1.2, 'night_view': 1.0}),
      ],
    ),
    _Step(
      key: 'avoid',
      prompt:
          "Is there anything you'd rather I keep off the menu? Allergies, dislikes, anything at all.",
      ack: "I'll keep it away.",
      freeText: true,
      negative: true,
    ),
    _Step(
      key: 'notes',
      prompt:
          'Last thing — tell me anything else worth remembering about you. Then your first recommendations will be waiting.',
      ack: 'Splendid.',
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
