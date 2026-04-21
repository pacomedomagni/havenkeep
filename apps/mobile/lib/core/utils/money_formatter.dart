import 'package:intl/intl.dart';

/// Centralized money formatting for HavenKeep.
///
/// Use these helpers instead of `toStringAsFixed` so currency rendering
/// stays consistent across every screen (dashboard, items, claims, paywall).
class Money {
  Money._();

  static final NumberFormat _currency =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);

  static final NumberFormat _currencyWhole =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

  /// Formats a currency amount with two decimals and thousands separators.
  ///
  /// `null` returns an em dash. `Money.format(1234.5)` → `$1,234.50`.
  static String format(num? amount) {
    if (amount == null) return '—';
    return _currency.format(amount);
  }

  /// Formats without decimals. `Money.formatWhole(1234)` → `$1,234`.
  static String formatWhole(num? amount) {
    if (amount == null) return '—';
    return _currencyWhole.format(amount);
  }

  /// Compact form with K / M suffixes for large values (hero cards).
  /// `Money.formatCompact(1234)` → `$1.2K`, `Money.formatCompact(1_500_000)` → `$1.5M`.
  static String formatCompact(num? amount) {
    if (amount == null) return '—';
    final value = amount.abs();
    final sign = amount < 0 ? '-' : '';
    if (value >= 1000000) {
      return '$sign\$${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 10000) {
      return '$sign\$${(value / 1000).toStringAsFixed(1)}K';
    }
    return _currencyWhole.format(amount);
  }

  /// Parses a user-entered price string into a double. Tolerant of `$`,
  /// commas, and whitespace. Returns `null` for invalid input.
  static double? parse(String? input) {
    if (input == null) return null;
    final cleaned = input.replaceAll(RegExp(r'[\$,\s]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }
}
