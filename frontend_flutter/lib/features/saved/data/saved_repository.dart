import '../../recommendations/domain/recommendation.dart';

/// Persisted list of saved experiences.
abstract interface class SavedRepository {
  Future<Set<String>> load();

  Future<Set<String>> add(String experienceId, {String? collection});

  Future<Set<String>> remove(String experienceId);

  Future<void> clear();

  Future<SavedExperience?> find(String experienceId);
}

/// Offline implementation. Kept separate from the Riverpod controller so the
/// persistence mechanism can change without touching the UI.
class LocalSavedRepository implements SavedRepository {
  LocalSavedRepository({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  final Map<String, SavedExperience> _items = {};
  int _counter = 0;

  @override
  Future<Set<String>> load() async => _items.keys.toSet();

  @override
  Future<Set<String>> add(String experienceId, {String? collection}) async {
    if (!_items.containsKey(experienceId)) {
      _items[experienceId] = SavedExperience(
        id: 'saved-${_counter++}',
        experienceId: experienceId,
        placeId: '',
        savedAt: _clock(),
        collection: collection,
      );
    }
    return _items.keys.toSet();
  }

  @override
  Future<Set<String>> remove(String experienceId) async {
    _items.remove(experienceId);
    return _items.keys.toSet();
  }

  @override
  Future<void> clear() async => _items.clear();

  @override
  Future<SavedExperience?> find(String experienceId) async =>
      _items[experienceId];
}
