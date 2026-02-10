/// Base exception hierarchy for HavenKeep app.
///
/// All custom exceptions should extend [AppException] to provide consistent
/// error handling throughout the application.

/// Base class for all application exceptions.
///
/// Provides:
/// - User-friendly error messages for UI display
/// - Developer-friendly messages for debugging
/// - Whether the error should be reported to crash reporting
/// - Original error and stack trace for debugging
abstract class AppException implements Exception {
  /// Developer-friendly error message (for logging/debugging).
  final String message;

  /// Optional error code for categorization.
  final String? code;

  /// Original error that caused this exception (if wrapped).
  final dynamic originalError;

  /// Stack trace captured at the point of exception creation.
  final StackTrace? stackTrace;

  AppException(
    this.message, {
    this.code,
    this.originalError,
    this.stackTrace,
  });

  /// User-friendly error message suitable for display in UI.
  ///
  /// Should be clear, actionable, and not expose technical details.
  String get userMessage;

  /// Whether this exception should be reported to crash reporting (Sentry).
  ///
  /// Returns `false` for expected errors like validation failures.
  /// Returns `true` for unexpected errors like network failures.
  bool get shouldReport => true;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write(runtimeType.toString());
    if (code != null) {
      buffer.write(' [$code]');
    }
    buffer.write(': $message');
    if (originalError != null) {
      buffer.write('\nCaused by: $originalError');
    }
    return buffer.toString();
  }
}

/// Exception thrown when user is not authenticated.
class UnauthorizedException extends AppException {
  UnauthorizedException({
    String message = 'User is not authenticated',
    String? code,
  }) : super(message, code: code ?? 'UNAUTHORIZED');

  @override
  String get userMessage => 'Please sign in to continue.';
}

/// Exception thrown when user lacks permission for an action.
class PermissionDeniedException extends AppException {
  PermissionDeniedException({
    String message = 'Permission denied',
    String? code,
  }) : super(message, code: code ?? 'PERMISSION_DENIED');

  @override
  String get userMessage => 'You don\'t have permission to perform this action.';
}

/// Exception thrown when a requested resource is not found.
class NotFoundException extends AppException {
  final String resourceType;

  NotFoundException({
    required this.resourceType,
    String? code,
  }) : super('$resourceType not found', code: code ?? 'NOT_FOUND');

  @override
  String get userMessage => '$resourceType not found. It may have been deleted.';
}

/// Exception thrown when an operation conflicts with existing state.
class ConflictException extends AppException {
  ConflictException({
    String message = 'Operation conflicts with current state',
    String? code,
  }) : super(message, code: code ?? 'CONFLICT');

  @override
  String get userMessage => 'This change conflicts with recent updates. Please refresh and try again.';
}

/// Exception thrown when the free plan item limit is reached.
class ItemLimitExceededException extends AppException {
  final int limit;
  final int currentCount;

  ItemLimitExceededException({
    required this.limit,
    required this.currentCount,
    String? code,
  }) : super(
          'Item limit exceeded: $currentCount/$limit',
          code: code ?? 'ITEM_LIMIT_EXCEEDED',
        );

  @override
  String get userMessage =>
      'You\'ve reached the free plan limit of $limit items. Upgrade to Premium for unlimited items.';

  @override
  bool get shouldReport => false; // Expected business logic, not an error
}

/// Base exception for database operations.
abstract class DatabaseException extends AppException {
  DatabaseException(
    String message, {
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
          message,
          code: code,
          originalError: originalError,
          stackTrace: stackTrace,
        );

  @override
  String get userMessage => 'Database error occurred. Please try again.';
}

/// Exception thrown when a database query fails.
class QueryException extends DatabaseException {
  QueryException({
    String message = 'Database query failed',
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
          message,
          code: code ?? 'QUERY_FAILED',
          originalError: originalError,
          stackTrace: stackTrace,
        );
}

/// Exception thrown when a database constraint is violated.
class ConstraintViolationException extends DatabaseException {
  ConstraintViolationException({
    String message = 'Database constraint violated',
    String? code,
    dynamic originalError,
  }) : super(
          message,
          code: code ?? 'CONSTRAINT_VIOLATION',
          originalError: originalError,
        );

  @override
  String get userMessage => 'This operation would create invalid data. Please check your input.';
}
