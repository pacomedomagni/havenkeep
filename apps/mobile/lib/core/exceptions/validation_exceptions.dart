import 'app_exceptions.dart';

/// Validation-related exceptions for HavenKeep app.

/// Base exception for validation errors.
///
/// These are user-facing errors that should not be reported to crash reporting.
class ValidationException extends AppException {
  /// Map of field names to error messages.
  final Map<String, String> fieldErrors;

  ValidationException(
    this.fieldErrors, {
    String message = 'Validation failed',
    String? code,
  }) : super(message, code: code ?? 'VALIDATION_ERROR');

  @override
  String get userMessage {
    if (fieldErrors.isEmpty) {
      return 'Please check your input and try again.';
    }
    if (fieldErrors.length == 1) {
      return fieldErrors.values.first;
    }
    return 'Please fix the following errors:\n${fieldErrors.values.join('\n')}';
  }

  @override
  bool get shouldReport => false; // User input errors shouldn't be reported
}

/// Exception thrown when a required field is missing.
class RequiredFieldException extends ValidationException {
  RequiredFieldException({
    required String fieldName,
    String? code,
  }) : super(
          {fieldName: '$fieldName is required'},
          message: 'Required field missing: $fieldName',
          code: code ?? 'REQUIRED_FIELD',
        );
}

/// Exception thrown when a field value is invalid.
class InvalidValueException extends ValidationException {
  InvalidValueException({
    required String fieldName,
    required String reason,
    String? code,
  }) : super(
          {fieldName: reason},
          message: 'Invalid value for $fieldName: $reason',
          code: code ?? 'INVALID_VALUE',
        );
}

/// Exception thrown when a field value exceeds maximum length.
class MaxLengthException extends ValidationException {
  final int maxLength;

  MaxLengthException({
    required String fieldName,
    required this.maxLength,
    String? code,
  }) : super(
          {fieldName: '$fieldName must be less than $maxLength characters'},
          message: 'Max length exceeded for $fieldName',
          code: code ?? 'MAX_LENGTH',
        );
}

/// Exception thrown when a field value is below minimum length.
class MinLengthException extends ValidationException {
  final int minLength;

  MinLengthException({
    required String fieldName,
    required this.minLength,
    String? code,
  }) : super(
          {fieldName: '$fieldName must be at least $minLength characters'},
          message: 'Min length not met for $fieldName',
          code: code ?? 'MIN_LENGTH',
        );
}

/// Exception thrown when a value is out of valid range.
class RangeException extends ValidationException {
  final num? min;
  final num? max;

  RangeException({
    required String fieldName,
    this.min,
    this.max,
    String? code,
  }) : super(
          {
            fieldName: _getMessage(fieldName, min, max),
          },
          message: 'Value out of range for $fieldName',
          code: code ?? 'OUT_OF_RANGE',
        );

  static String _getMessage(String fieldName, num? min, num? max) {
    if (min != null && max != null) {
      return '$fieldName must be between $min and $max';
    } else if (min != null) {
      return '$fieldName must be at least $min';
    } else if (max != null) {
      return '$fieldName must be at most $max';
    } else {
      return '$fieldName is out of valid range';
    }
  }
}

/// Exception thrown when a format/pattern validation fails.
class FormatException extends ValidationException {
  FormatException({
    required String fieldName,
    required String expectedFormat,
    String? code,
  }) : super(
          {fieldName: '$fieldName must match format: $expectedFormat'},
          message: 'Invalid format for $fieldName',
          code: code ?? 'INVALID_FORMAT',
        );
}
