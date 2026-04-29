import 'package:intl/intl.dart';

/// Centralized money formatting for HavenKeep.
///
/// 3.5: HavenKeep v1 is USD-only — the backend bills in USD via Stripe
/// and every form prefixes a hard-coded `$`. The unused `locale`
/// parameter has been dropped to make that explicit; threading locale
/// through every call site is a much larger lift and is parked until we
/// take payment in a non-USD currency. Surface "Prices in USD" copy on
/// the form labels (manual entry, claim cost) so non-US users aren't
/// confused.
///
/// Money values that come off the wire from Postgres `DECIMAL` columns
/// (item.price, warranty purchase price, claim amount, maintenance cost)
/// are now carried as `String?` to preserve cents — see Phase 8. Use
/// [format] for those — it accepts `num?` *or* a numeric string and
/// keeps the cent-accurate value end-to-end.
class Money {
  Money._();

  static const String _locale = 'en_US';

  // S2-R: cache one NumberFormat per decimalDigits so the hot path
  // doesn't allocate per call. Locale is fixed to en_US (see class doc).
  static final Map<int, NumberFormat> _currencyCache = {};

  static NumberFormat _currencyFor(int decimalDigits) {
    return _currencyCache.putIfAbsent(
      decimalDigits,
      () => NumberFormat.currency(
        locale: _locale,
        symbol: '\$',
        decimalDigits: decimalDigits,
      ),
    );
  }

  /// Formats a currency amount with two decimals and thousands separators.
  ///
  /// `null` returns an em dash. Accepts a `num` or a `String` carrying a
  /// decimal value (e.g. `"1234.50"`). Strings that don't parse fall
  /// back to the em dash so a malformed wire value never crashes the UI.
  ///
  /// `Money.format(1234.5)` → `$1,234.50`.
  static String format(Object? amount) {
    final value = _toNum(amount);
    if (value == null) return '—';
    return _currencyFor(2).format(value);
  }

  /// Formats without decimals. `Money.formatWhole(1234)` → `$1,234`.
  /// Accepts a `num` or numeric string for the same reason as [format].
  static String formatWhole(Object? amount) {
    final value = _toNum(amount);
    if (value == null) return '—';
    return _currencyFor(0).format(value);
  }

  /// Compact form with K / M suffixes for large values (hero cards).
  /// `Money.formatCompact(1234)` → `$1.2K`, `Money.formatCompact(1_500_000)` → `$1.5M`.
  static String formatCompact(Object? amount) {
    final value = _toNum(amount);
    if (value == null) return '—';
    final magnitude = value.abs();
    final sign = value < 0 ? '-' : '';
    if (magnitude >= 1000000) {
      return '$sign\$${(magnitude / 1000000).toStringAsFixed(1)}M';
    }
    if (magnitude >= 10000) {
      return '$sign\$${(magnitude / 1000).toStringAsFixed(1)}K';
    }
    return _currencyFor(0).format(value);
  }

  /// Parses a user-entered price string into a normalized DECIMAL string
  /// (e.g. `"$1,234.50"` → `"1234.50"`). Returns `null` for invalid
  /// input. The two-decimal form is what the API expects on the wire.
  static String? parseToDecimal(String? input) {
    final value = parseToDouble(input);
    if (value == null) return null;
    return value.toStringAsFixed(2);
  }

  /// Parses a user-entered price string into a double. Tolerant of `$`,
  /// commas, and whitespace. Returns `null` for invalid input. Use
  /// [parseToDecimal] when you need to send the value to the API.
  static double? parseToDouble(String? input) {
    if (input == null) return null;
    final cleaned = input.replaceAll(RegExp(r'[\$,\s]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Sums a list of decimal-string amounts as doubles. Non-parseable
  /// entries are treated as zero, matching the prior `?? 0` behavior in
  /// callers that aggregate prices for hero cards.
  static double sumDecimals(Iterable<String?> values) {
    double total = 0;
    for (final v in values) {
      final n = _toNum(v);
      if (n != null) total += n.toDouble();
    }
    return total;
  }

  /// Coerces either a `num` or a numeric string to a `num`. Returns
  /// `null` for null inputs or strings that fail to parse.
  static num? _toNum(Object? value) {
    if (value == null) return null;
    if (value is num) return value;
    if (value is String) {
      if (value.isEmpty) return null;
      return num.tryParse(value);
    }
    return null;
  }
}
