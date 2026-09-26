import 'package:intl/intl.dart';

/// Formatting helpers shared across the UI.
abstract final class Fmt {
  Fmt._();

  static final NumberFormat _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  /// `₹800`, `₹1.5K` for large values.
  static String inr(num value) {
    if (value >= 100000) {
      return '₹${(value / 100000).toStringAsFixed(1)}L';
    }
    if (value >= 1000) {
      return '₹${(value / 1000).toStringAsFixed(1)}K';
    }
    return _inr.format(value);
  }

  /// Exact rupees, no decimals: `₹800`.
  static String inrExact(num value) => '₹${value.round()}';

  /// `1.2K`, `3.4K`, `820`.
  static String compactCount(num value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return '${value.round()}';
  }

  /// `45 min`, `1h 20m`, `2h`.
  static String duration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// `1h 20m` style used for plan totals.
  static String durationLong(int minutes) => duration(minutes);

  /// `8 AM – 11 PM` from `08:00` / `23:00`.
  static String timeOfDay(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return hhmm;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final period = h >= 12 ? 'PM' : 'AM';
    var hour = h % 12;
    if (hour == 0) hour = 12;
    final minuteText = m == 0 ? '' : ':${m.toString().padLeft(2, '0')}';
    return '$hour$minuteText $period';
  }

  /// `8 AM – 11 PM` range.
  static String timeRange(String open, String close) =>
      '${timeOfDay(open)} – ${timeOfDay(close)}';

  /// `2 hours ago`, `just now` style for chat/history.
  static String relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}
