import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../exceptions/app_exceptions.dart';
import '../exceptions/network_exceptions.dart';
import '../services/logging_service.dart';

/// Centralized error handling for the HavenKeep app.
///
/// Provides consistent error handling across the app with:
/// - Automatic error logging
/// - User-friendly error messages
/// - Optional UI feedback (snackbars)
/// - Error reporting to logging service
class ErrorHandler {
  /// Converts any error into a user-friendly message string.
  ///
  /// Checks for known exception types and returns their user message.
  /// Falls back to a generic message for unknown errors.
  static String getUserMessage(dynamic error) {
    if (error == null) return 'Something went wrong. Please try again.';

    if (error is AppException) return error.userMessage;

    if (error is ApiException) {
      switch (error.statusCode) {
        case 400:
          return error.message.isNotEmpty && error.message != 'Request failed'
              ? error.message
              : 'Invalid request. Please check your input.';
        case 401:
          return 'Your session has expired. Please sign in again.';
        case 403:
          return 'You don\'t have permission for this action.';
        case 404:
          return 'The requested item was not found.';
        case 408:
          return 'Request timed out. Please try again.';
        case 409:
          return error.message.isNotEmpty && error.message != 'Request failed'
              ? error.message
              : 'This change conflicts with recent updates. Please refresh and try again.';
        case 429:
          return 'Too many requests. Please wait a moment and try again.';
        default:
          if (error.statusCode >= 500) {
            return 'Server error. Please try again later.';
          }
          return 'Something went wrong. Please try again.';
      }
    }

    if (error is SocketException) {
      return 'No internet connection. Please check your network and try again.';
    }

    if (error is TimeoutException) {
      return 'Request timed out. Please try again.';
    }

    return 'Something went wrong. Please try again.';
  }

  /// Handles an async operation with consistent error handling.
  ///
  /// Catches all exceptions, logs them, shows user feedback, and rethrows.
  ///
  /// Example:
  /// ```dart
  /// await ErrorHandler.handle(
  ///   operation: () => repository.createItem(item),
  ///   context: context,
  ///   userMessage: 'Failed to create item',
  /// );
  /// ```
  static Future<T> handle<T>({
    required Future<T> Function() operation,
    BuildContext? context,
    String? userMessage,
    bool showSnackbar = true,
    Map<String, dynamic>? logContext,
  }) async {
    try {
      return await operation();
    } on AppException catch (e, stack) {
      // Log to logging service if needed
      if (e.shouldReport) {
        LoggingService.error(
          e.message,
          e,
          stack,
          {
            ...?logContext,
            'errorCode': e.code,
            'userMessage': userMessage,
          },
        );
      } else {
        LoggingService.warn(
          e.message,
          {
            ...?logContext,
            'errorCode': e.code,
          },
        );
      }

      // Show user feedback
      if (context != null && context.mounted && showSnackbar) {
        _showErrorSnackbar(
          context,
          userMessage ?? e.userMessage,
          canRetry: e is NetworkException,
        );
      }

      rethrow;
    } on SocketException catch (e, stack) {
      // Network error (no internet connection)
      final exception = NoConnectionException(
        originalError: e,
        stackTrace: stack,
      );

      LoggingService.error('No connection', e, stack, logContext);

      if (context != null && context.mounted && showSnackbar) {
        _showErrorSnackbar(
          context,
          exception.userMessage,
          canRetry: true,
        );
      }

      throw exception;
    } on TimeoutException catch (e, stack) {
      // Request timeout
      final exception = TimeoutException(
        originalError: e,
        stackTrace: stack,
      );

      LoggingService.error('Request timeout', e, stack, logContext);

      if (context != null && context.mounted && showSnackbar) {
        _showErrorSnackbar(
          context,
          exception.userMessage,
          canRetry: true,
        );
      }

      throw exception;
    } catch (e, stack) {
      // Unknown error
      LoggingService.fatal(
        'Unexpected error: ${e.runtimeType}',
        e,
        stack,
        logContext,
      );

      if (context != null && context.mounted && showSnackbar) {
        _showErrorSnackbar(
          context,
          userMessage ?? 'An unexpected error occurred. Please try again.',
        );
      }

      rethrow;
    }
  }

  /// Shows an error snackbar with optional retry action.
  static void _showErrorSnackbar(
    BuildContext context,
    String message, {
    bool canRetry = false,
    VoidCallback? onRetry,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: HavenColors.expired,
        behavior: SnackBarBehavior.floating,
        action: canRetry && onRetry != null
            ? SnackBarAction(
                label: 'Retry',
                textColor: HavenColors.textPrimary,
                onPressed: onRetry,
              )
            : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Shows a success snackbar.
  static void showSuccess(
    BuildContext context,
    String message,
  ) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: HavenColors.active,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Shows an info snackbar.
  static void showInfo(
    BuildContext context,
    String message,
  ) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: HavenColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Logs an error without throwing.
  ///
  /// Useful for non-critical errors that shouldn't interrupt the flow.
  static void logError(
    String message,
    dynamic error, [
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  ]) {
    if (error is AppException && !error.shouldReport) {
      LoggingService.warn(message, context);
    } else {
      LoggingService.error(message, error, stackTrace, context);
    }
  }

  /// Handles an error synchronously (for use in builders, etc.).
  ///
  /// Only logs the error, does not show UI feedback.
  static void handleSync(
    dynamic error,
    StackTrace stackTrace, {
    String? message,
    Map<String, dynamic>? context,
  }) {
    if (error is AppException) {
      if (error.shouldReport) {
        LoggingService.error(
          message ?? error.message,
          error,
          stackTrace,
          context,
        );
      }
    } else {
      LoggingService.error(
        message ?? 'Synchronous error',
        error,
        stackTrace,
        context,
      );
    }
  }
}
