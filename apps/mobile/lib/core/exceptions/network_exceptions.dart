import 'app_exceptions.dart';

/// Network-related exceptions for HavenKeep app.

/// Base exception for all network-related errors.
class NetworkException extends AppException {
  final int? statusCode;

  NetworkException(
    String message, {
    this.statusCode,
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
          message,
          code: code ?? 'NETWORK_ERROR',
          originalError: originalError,
          stackTrace: stackTrace,
        );

  @override
  String get userMessage {
    if (statusCode != null) {
      switch (statusCode) {
        case 400:
          return 'Invalid request. Please check your input.';
        case 401:
          return 'Your session has expired. Please sign in again.';
        case 403:
          return 'You don\'t have permission for this action.';
        case 404:
          return 'Requested resource not found.';
        case 408:
          return 'Request timed out. Please try again.';
        case 429:
          return 'Too many requests. Please wait a moment and try again.';
        case 500:
        case 502:
        case 503:
        case 504:
          return 'Server error. Please try again later.';
        default:
          return 'Network error occurred. Please try again.';
      }
    }
    return 'Network error. Please check your connection and try again.';
  }
}

/// Exception thrown when there's no internet connection.
class NoConnectionException extends NetworkException {
  NoConnectionException({
    String message = 'No internet connection',
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
          message,
          code: 'NO_CONNECTION',
          originalError: originalError,
          stackTrace: stackTrace,
        );

  @override
  String get userMessage => 'No internet connection. Please check your network and try again.';
}

/// Exception thrown when a request times out.
class TimeoutException extends NetworkException {
  TimeoutException({
    String message = 'Request timed out',
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
          message,
          code: 'TIMEOUT',
          originalError: originalError,
          stackTrace: stackTrace,
        );

  @override
  String get userMessage => 'Request took too long. Please try again.';
}

/// Exception thrown when the server returns an error.
class ServerException extends NetworkException {
  ServerException({
    String message = 'Server error',
    int? statusCode,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(
          message,
          statusCode: statusCode,
          code: 'SERVER_ERROR',
          originalError: originalError,
          stackTrace: stackTrace,
        );
}

/// Exception thrown when a rate limit is exceeded.
class RateLimitException extends NetworkException {
  final Duration? retryAfter;

  RateLimitException({
    String message = 'Rate limit exceeded',
    this.retryAfter,
    dynamic originalError,
  }) : super(
          message,
          statusCode: 429,
          code: 'RATE_LIMIT',
          originalError: originalError,
        );

  @override
  String get userMessage {
    if (retryAfter != null) {
      final seconds = retryAfter!.inSeconds;
      return 'Too many requests. Please wait $seconds seconds and try again.';
    }
    return 'Too many requests. Please wait a moment and try again.';
  }
}
