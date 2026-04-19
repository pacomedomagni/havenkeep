/// Parse a user-entered price string into a double.
///
/// Accepts either `.` or `,` as the decimal separator and tolerates thousands
/// grouping characters (`,`, `.`, whitespace, `'`). Returns `null` if the
/// value can't be interpreted as a non-negative number.
///
/// Rationale: `double.tryParse` is locale-blind and silently returns `null`
/// for `"19,99"`. Flutter form callers have been doing that parse directly,
/// turning German/French/etc. input into empty saves.
double? parsePriceInput(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;

  // Remove common currency prefixes/suffixes and whitespace.
  s = s.replaceAll(RegExp(r"[\s\u00A0']"), '');
  s = s.replaceAll(RegExp(r'[^0-9.,\-]'), '');
  if (s.isEmpty) return null;

  final hasComma = s.contains(',');
  final hasDot = s.contains('.');

  if (hasComma && hasDot) {
    // Whichever separator appears last is treated as the decimal.
    if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (hasComma && !hasDot) {
    // Ambiguous: "1,234" could be 1234 (US thousands) or 1.234 (EU decimal).
    // If the comma is followed by exactly 3 digits and nothing else, treat
    // it as a thousands separator; otherwise treat it as a decimal.
    final match = RegExp(r'^-?\d{1,3}(,\d{3})+$').hasMatch(s);
    s = match ? s.replaceAll(',', '') : s.replaceAll(',', '.');
  }

  final v = double.tryParse(s);
  if (v == null) return null;
  if (v.isNaN || v.isInfinite) return null;
  return v;
}
