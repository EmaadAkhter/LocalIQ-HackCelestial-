/// Converts snake_case / kebab-case API keys into camelCase Dart maps and
/// back. Keeps `fromJson` mappers declarative instead of hand-written.
extension JsonMapX on Map<String, dynamic> {
  /// Reads a value trying [camel] first, then [snake], then [kebab].
  dynamic pick(String key) {
    if (containsKey(key)) return this[key];
    final snake = _toSnake(key);
    if (containsKey(snake)) return this[snake];
    final kebab = _toKebab(key);
    if (containsKey(kebab)) return this[kebab];
    return null;
  }

  String? string(String key) => pick(key)?.toString();

  String? stringOrNull(String key) {
    final value = pick(key);
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty || text == 'null' ? null : text;
  }

  int intValue(String key, {int fallback = 0}) {
    final value = pick(key);
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  int? intOrNull(String key) {
    final value = pick(key);
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double doubleValue(String key, {double fallback = 0}) {
    final value = pick(key);
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  double? doubleOrNull(String key) {
    final value = pick(key);
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool boolValue(String key, {bool fallback = false}) {
    final value = pick(key);
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final text = value.toLowerCase();
      if (text == 'true' || text == '1' || text == 'yes') return true;
      if (text == 'false' || text == '0' || text == 'no') return false;
    }
    return fallback;
  }

  List<String> stringList(String key) {
    final value = pick(key);
    if (value is List) {
      return value.map((e) => e.toString()).toList(growable: false);
    }
    if (value is String && value.isNotEmpty) return [value];
    return const [];
  }

  Map<String, dynamic> mapOrEmpty(String key) {
    final value = pick(key);
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  List<Map<String, dynamic>> mapList(String key) {
    final value = pick(key);
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }
    return const [];
  }

  static String _toSnake(String input) {
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch.toUpperCase() == ch && ch.toLowerCase() != ch) {
        buffer.write('_');
        buffer.write(ch.toLowerCase());
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  static String _toKebab(String input) => input.replaceAll('_', '-');
}
