/// Form validation utilities for HavenKeep.
///
/// Provides reusable validators for form fields with user-friendly error messages.
class Validators {
  /// Validates that a field is not empty.
  ///
  /// Returns error message if validation fails, null if valid.
  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Validates minimum length.
  static String? minLength(
    String? value,
    int min, {
    String? fieldName,
  }) {
    if (value == null) return null; // Allow empty if not required

    if (value.length < min) {
      return '${fieldName ?? 'This field'} must be at least $min characters';
    }
    return null;
  }

  /// Validates maximum length.
  static String? maxLength(
    String? value,
    int max, {
    String? fieldName,
  }) {
    if (value == null) return null;

    if (value.length > max) {
      return '${fieldName ?? 'This field'} must be less than $max characters';
    }
    return null;
  }

  /// Validates exact length.
  static String? exactLength(
    String? value,
    int length, {
    String? fieldName,
  }) {
    if (value == null) return null;

    if (value.length != length) {
      return '${fieldName ?? 'This field'} must be exactly $length characters';
    }
    return null;
  }

  /// Validates price value.
  ///
  /// Checks:
  /// - Valid number format
  /// - Non-negative
  /// - Reasonable range (< $10M)
  static String? price(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Allow empty if not required
    }

    final parsed = double.tryParse(value.replaceAll(RegExp(r'[^\d.]'), ''));
    if (parsed == null) {
      return 'Please enter a valid price';
    }

    if (parsed < 0) {
      return 'Price cannot be negative';
    }

    if (parsed > 10000000) {
      return 'Price seems unreasonably high';
    }

    return null;
  }

  /// Validates warranty months.
  ///
  /// Typical range: 1 month to 25 years (300 months)
  static String? warrantyMonths(int? value) {
    if (value == null) {
      return 'Warranty duration is required';
    }

    if (value < 0) {
      return 'Warranty months cannot be negative';
    }

    if (value == 0) {
      return 'Warranty must be at least 1 month';
    }

    if (value > 300) {
      // 25 years
      return 'Warranty period seems too long (max 25 years)';
    }

    return null;
  }

  /// Validates serial number format.
  ///
  /// Checks:
  /// - Minimum length (3 characters)
  /// - Only alphanumeric and hyphens
  static String? serialNumber(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Allow empty if not required
    }

    if (value.length < 3) {
      return 'Serial number too short (min 3 characters)';
    }

    if (!RegExp(r'^[A-Z0-9\-]+$', caseSensitive: false).hasMatch(value)) {
      return 'Serial number can only contain letters, numbers, and hyphens';
    }

    return null;
  }

  /// Validates model number format.
  ///
  /// Similar to serial number.
  static String? modelNumber(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    if (value.length < 2) {
      return 'Model number too short (min 2 characters)';
    }

    if (!RegExp(r'^[A-Z0-9\-]+$', caseSensitive: false).hasMatch(value)) {
      return 'Model number can only contain letters, numbers, and hyphens';
    }

    return null;
  }

  /// Validates email format.
  static String? email(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    // Basic email regex (RFC 5322 simplified)
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  /// Validates phone number format.
  ///
  /// Accepts various formats:
  /// - (555) 123-4567
  /// - 555-123-4567
  /// - 5551234567
  /// - +1 555 123 4567
  static String? phoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    // Remove formatting characters
    final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.length < 10) {
      return 'Phone number must have at least 10 digits';
    }

    if (digitsOnly.length > 15) {
      return 'Phone number too long';
    }

    return null;
  }

  /// Validates URL format.
  static String? url(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      return 'Please enter a valid URL (must start with http:// or https://)';
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'URL must use http:// or https://';
    }

    return null;
  }

  /// Validates ZIP code format (US).
  ///
  /// Accepts:
  /// - 12345
  /// - 12345-6789
  static String? zipCode(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final zipRegex = RegExp(r'^\d{5}(-\d{4})?$');
    if (!zipRegex.hasMatch(value)) {
      return 'Please enter a valid ZIP code (12345 or 12345-6789)';
    }

    return null;
  }

  /// Validates that a date is not in the future.
  static String? notInFuture(DateTime? value, {String? fieldName}) {
    if (value == null) {
      return null;
    }

    if (value.isAfter(DateTime.now())) {
      return '${fieldName ?? 'Date'} cannot be in the future';
    }

    return null;
  }

  /// Validates that a date is within a reasonable range for purchase dates.
  ///
  /// Accepts dates within the last 50 years.
  static String? reasonablePurchaseDate(DateTime? value) {
    if (value == null) {
      return null;
    }

    final now = DateTime.now();
    final fiftyYearsAgo = DateTime(now.year - 50, now.month, now.day);

    if (value.isBefore(fiftyYearsAgo)) {
      return 'Purchase date seems too far in the past';
    }

    if (value.isAfter(now)) {
      return 'Purchase date cannot be in the future';
    }

    return null;
  }

  /// Combines multiple validators.
  ///
  /// Returns the first error message encountered, or null if all pass.
  ///
  /// Example:
  /// ```dart
  /// validator: Validators.combine([
  ///   (v) => Validators.required(v, fieldName: 'Item name'),
  ///   (v) => Validators.minLength(v, 2, fieldName: 'Item name'),
  ///   (v) => Validators.maxLength(v, 100, fieldName: 'Item name'),
  /// ])
  /// ```
  static String? Function(String?) combine(
    List<String? Function(String?)> validators,
  ) {
    return (value) {
      for (final validator in validators) {
        final error = validator(value);
        if (error != null) {
          return error;
        }
      }
      return null;
    };
  }

  /// Matches a regular expression pattern.
  static String? pattern(
    String? value,
    RegExp pattern, {
    String? errorMessage,
  }) {
    if (value == null || value.isEmpty) {
      return null;
    }

    if (!pattern.hasMatch(value)) {
      return errorMessage ?? 'Invalid format';
    }

    return null;
  }

  /// Validates numeric range.
  static String? numericRange(
    num? value,
    num min,
    num max, {
    String? fieldName,
  }) {
    if (value == null) {
      return null;
    }

    if (value < min || value > max) {
      return '${fieldName ?? 'Value'} must be between $min and $max';
    }

    return null;
  }
}
