import 'dart:io';

import 'package:flutter/material.dart';

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
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        action: canRetry && onRetry != null
            ? SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
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
        backgroundColor: Colors.green[700],
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
        backgroundColor: Colors.blue[700],
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
