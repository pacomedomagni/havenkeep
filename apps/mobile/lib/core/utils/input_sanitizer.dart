/// Input sanitization utilities for HavenKeep.
///
/// Removes potentially dangerous characters from user input to prevent:
/// - XSS attacks
/// - SQL injection
/// - Control character exploits
/// - Data corruption
class InputSanitizer {
  /// Sanitizes text input by removing dangerous characters.
  ///
  /// Removes:
  /// - Null bytes (\x00)
  /// - Control characters (except newline, tab, carriage return)
  /// - Leading/trailing whitespace
  ///
  /// Optionally truncates to [maxLength].
  static String sanitizeText(String input, {int? maxLength}) {
    // Trim whitespace
    var result = input.trim();

    // Remove null bytes
    result = result.replaceAll('\u0000', '');

    // Remove control characters except newline (\n), tab (\t), and carriage return (\r)
    // Control characters are in range \x00-\x1F and \x7F
    // Keep: \x09 (tab), \x0A (newline), \x0D (carriage return)
    result = result.replaceAll(
      RegExp(r'[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F]'),
      '',
    );

    // Truncate if max length specified
    if (maxLength != null && result.length > maxLength) {
      result = result.substring(0, maxLength);
    }

    return result;
  }

  /// Sanitizes numeric price input.
  ///
  /// Extracts only digits and decimal point.
  /// Returns null if unable to parse as valid number.
  static double? sanitizePrice(String input) {
    // Remove everything except digits and decimal point
    final cleaned = input.replaceAll(RegExp(r'[^\d.]'), '');

    if (cleaned.isEmpty) {
      return null;
    }

    // Parse as double
    final value = double.tryParse(cleaned);

    // Validate range
    if (value == null || value < 0 || value > 10000000) {
      return null; // Unreasonable price
    }

    return value;
  }

  /// Sanitizes integer input (warranty months, counts, etc).
  ///
  /// Extracts only digits.
  /// Returns null if unable to parse.
  static int? sanitizeInteger(String input) {
    // Remove everything except digits
    final cleaned = input.replaceAll(RegExp(r'[^\d]'), '');

    if (cleaned.isEmpty) {
      return null;
    }

    return int.tryParse(cleaned);
  }

  /// Sanitizes URL input.
  ///
  /// Returns null if not a valid URL.
  /// Ensures URL has a scheme (http/https).
  static String? sanitizeUrl(String input) {
    final trimmed = input.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    // Try to parse as URI
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      return null;
    }

    // Only allow http/https
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }

    return uri.toString();
  }

  /// Sanitizes email input.
  ///
  /// Basic sanitization - removes whitespace and converts to lowercase.
  /// Does NOT validate email format (use validator for that).
  static String sanitizeEmail(String input) {
    return input.trim().toLowerCase();
  }

  /// Sanitizes phone number input.
  ///
  /// Removes everything except digits, +, -, (, ), and spaces.
  static String sanitizePhoneNumber(String input) {
    final result = input.replaceAll(RegExp(r'[^\d+\-() ]'), '');
    return result.trim();
  }

  /// Sanitizes serial number input.
  ///
  /// Removes special characters, keeps alphanumeric and hyphens.
  /// Converts to uppercase for consistency.
  static String sanitizeSerialNumber(String input) {
    final result = input
        .replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '')
        .toUpperCase()
        .trim();
    return result;
  }

  /// Sanitizes model number input.
  ///
  /// Similar to serial number but preserves case.
  static String sanitizeModelNumber(String input) {
    final result = input
        .replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '')
        .trim();
    return result;
  }

  /// Sanitizes a single-line text field (no newlines allowed).
  ///
  /// Removes all newlines and control characters.
  static String sanitizeSingleLine(String input, {int? maxLength}) {
    var result = sanitizeText(input, maxLength: maxLength);

    // Remove all newlines
    result = result.replaceAll('\n', ' ');
    result = result.replaceAll('\r', ' ');

    // Collapse multiple spaces
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    return result.trim();
  }

  /// Sanitizes multi-line text (notes, descriptions).
  ///
  /// Allows newlines but removes dangerous control characters.
  static String sanitizeMultiLine(String input, {int? maxLength}) {
    return sanitizeText(input, maxLength: maxLength);
  }

  /// Escapes special characters for safe display (prevents XSS).
  ///
  /// Escapes:
  /// - < to &lt;
  /// - > to &gt;
  /// - & to &amp;
  /// - " to &quot;
  /// - ' to &#x27;
  static String escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  /// Strips all HTML tags from input.
  ///
  /// Useful for accepting rich text but storing plain text.
  static String stripHtmlTags(String input) {
    return input.replaceAll(RegExp(r'<[^>]*>'), '');
  }
}
