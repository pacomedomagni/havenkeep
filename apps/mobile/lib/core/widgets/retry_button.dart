import 'package:flutter/material.dart';

/// A reusable retry button widget with loading state.
///
/// Provides consistent retry UX with:
/// - Loading state during retry
/// - Disabled state while processing
/// - Optional custom label
/// - Configurable style
///
/// Example:
/// ```dart
/// RetryButton(
///   onRetry: () async {
///     await repository.fetchItems();
///   },
/// )
/// ```
class RetryButton extends StatefulWidget {
  /// Callback when the retry button is pressed.
  /// Should return a Future that completes when the retry is done.
  final Future<void> Function() onRetry;

  /// Optional label for the button (defaults to "Retry").
  final String? label;

  /// Optional icon (defaults to refresh icon).
  final IconData? icon;

  /// Whether to show icon (defaults to true).
  final bool showIcon;

  /// Button style variant.
  final RetryButtonStyle style;

  /// Whether the button is disabled.
  final bool disabled;

  const RetryButton({
    super.key,
    required this.onRetry,
    this.label,
    this.icon,
    this.showIcon = true,
    this.style = RetryButtonStyle.elevated,
    this.disabled = false,
  });

  @override
  State<RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<RetryButton> {
  bool _isRetrying = false;

  Future<void> _handleRetry() async {
    if (_isRetrying || widget.disabled) return;

    setState(() {
      _isRetrying = true;
    });

    try {
      await widget.onRetry();
    } finally {
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label ?? 'Retry';
    final icon = widget.icon ?? Icons.refresh;
    final isDisabled = widget.disabled || _isRetrying;

    switch (widget.style) {
      case RetryButtonStyle.elevated:
        return ElevatedButton.icon(
          onPressed: isDisabled ? null : _handleRetry,
          icon: _buildIcon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
          ),
        );

      case RetryButtonStyle.outlined:
        return OutlinedButton.icon(
          onPressed: isDisabled ? null : _handleRetry,
          icon: _buildIcon(icon),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
          ),
        );

      case RetryButtonStyle.text:
        return TextButton.icon(
          onPressed: isDisabled ? null : _handleRetry,
          icon: _buildIcon(icon),
          label: Text(label),
        );

      case RetryButtonStyle.iconOnly:
        return IconButton(
          onPressed: isDisabled ? null : _handleRetry,
          icon: _buildIcon(icon, size: 24),
          tooltip: label,
        );
    }
  }

  Widget _buildIcon(IconData iconData, {double? size}) {
    if (!widget.showIcon) {
      return const SizedBox.shrink();
    }

    if (_isRetrying) {
      return SizedBox(
        width: size ?? 18,
        height: size ?? 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.onPrimary,
          ),
        ),
      );
    }

    return Icon(iconData, size: size);
  }
}

/// Style variants for RetryButton.
enum RetryButtonStyle {
  /// Elevated button (filled background).
  elevated,

  /// Outlined button (border only).
  outlined,

  /// Text button (no background or border).
  text,

  /// Icon button only (no text label).
  iconOnly,
}

/// A specialized retry banner for showing persistent retry options.
///
/// Useful for scenarios where you want to show a retry option
/// at the top of a list or screen without replacing the content.
class RetryBanner extends StatelessWidget {
  /// The error message to display.
  final String message;

  /// Callback when the retry button is pressed.
  final Future<void> Function() onRetry;

  /// Whether to show the banner.
  final bool show;

  /// Optional custom background color.
  final Color? backgroundColor;

  const RetryBanner({
    super.key,
    required this.message,
    required this.onRetry,
    this.show = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.orange[50],
        border: Border(
          bottom: BorderSide(
            color: Colors.orange[200]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange[700],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.orange[900],
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          RetryButton(
            onRetry: onRetry,
            style: RetryButtonStyle.outlined,
            label: 'Retry',
          ),
        ],
      ),
    );
  }
}

/// A pull-to-refresh wrapper with retry logic.
///
/// Combines RefreshIndicator with retry functionality.
class RetryRefreshWrapper extends StatelessWidget {
  /// The child widget to wrap.
  final Widget child;

  /// Callback when pull-to-refresh is triggered.
  final Future<void> Function() onRefresh;

  const RetryRefreshWrapper({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: child,
    );
  }
}
