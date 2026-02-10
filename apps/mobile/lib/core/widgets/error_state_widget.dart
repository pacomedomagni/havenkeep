import 'package:flutter/material.dart';

/// A reusable widget for displaying error states with optional retry action.
///
/// Provides consistent error UX across the app with:
/// - Error icon and message
/// - Optional retry button
/// - Optional custom action button
/// - Responsive layout
///
/// Example:
/// ```dart
/// ErrorStateWidget(
///   message: 'Failed to load items',
///   onRetry: () => ref.refresh(itemsProvider),
/// )
/// ```
class ErrorStateWidget extends StatelessWidget {
  /// The error message to display to the user.
  final String message;

  /// Optional callback when the retry button is pressed.
  final VoidCallback? onRetry;

  /// Optional custom action button label.
  final String? actionLabel;

  /// Optional custom action callback.
  final VoidCallback? onAction;

  /// Optional icon to display (defaults to error_outline).
  final IconData? icon;

  /// Optional additional details to show below the main message.
  final String? details;

  /// Whether to show a compact version (for inline errors).
  final bool compact;

  const ErrorStateWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.details,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactError(context);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon ?? Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.red[700],
                  ),
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            if (onRetry != null)
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactError(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(
            icon ?? Icons.error_outline,
            size: 24,
            color: Colors.red[700],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.red[900],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (details != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    details!,
                    style: TextStyle(
                      color: Colors.red[700],
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 12),
            IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              color: Colors.red[700],
              tooltip: 'Retry',
            ),
          ],
        ],
      ),
    );
  }
}

/// A specialized error widget for network/connectivity errors.
class NetworkErrorWidget extends StatelessWidget {
  final VoidCallback? onRetry;
  final bool compact;

  const NetworkErrorWidget({
    super.key,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorStateWidget(
      message: 'No internet connection',
      details: 'Please check your network settings and try again.',
      icon: Icons.wifi_off,
      onRetry: onRetry,
      compact: compact,
    );
  }
}

/// A specialized error widget for empty states.
class EmptyStateWidget extends StatelessWidget {
  final String message;
  final String? details;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateWidget({
    super.key,
    required this.message,
    this.details,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon ?? Icons.inbox_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[700],
                  ),
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: 8),
              Text(
                details!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A widget that displays loading, error, or data states.
///
/// Simplifies async state handling by providing a single widget
/// that handles all three states.
///
/// Example:
/// ```dart
/// AsyncStateBuilder<List<Item>>(
///   asyncValue: itemsAsync,
///   builder: (items) => ListView.builder(...),
///   onRetry: () => ref.refresh(itemsProvider),
/// )
/// ```
class AsyncStateBuilder<T> extends StatelessWidget {
  /// The async value to render.
  final AsyncSnapshot<T> asyncValue;

  /// Builder for the data state.
  final Widget Function(T data) builder;

  /// Optional retry callback for error state.
  final VoidCallback? onRetry;

  /// Optional loading widget (defaults to CircularProgressIndicator).
  final Widget? loadingWidget;

  /// Optional error message override.
  final String? errorMessage;

  const AsyncStateBuilder({
    super.key,
    required this.asyncValue,
    required this.builder,
    this.onRetry,
    this.loadingWidget,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (asyncValue.connectionState == ConnectionState.waiting) {
      return loadingWidget ??
          const Center(
            child: CircularProgressIndicator(),
          );
    }

    if (asyncValue.hasError) {
      final error = asyncValue.error;
      final message = errorMessage ??
          (error?.toString() ?? 'An unexpected error occurred');

      return ErrorStateWidget(
        message: message,
        onRetry: onRetry,
      );
    }

    if (!asyncValue.hasData) {
      return ErrorStateWidget(
        message: 'No data available',
        onRetry: onRetry,
      );
    }

    return builder(asyncValue.data as T);
  }
}
