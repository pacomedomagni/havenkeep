import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Branded snack helper. Uses the theme's floating SnackBar config plus a
/// leading icon and matching haptic so every feature gets the same feedback
/// without wiring it per call site.
void showHavenSnackBar(
  BuildContext context, {
  required String message,
  bool isError = false,
  bool isSuccess = false,
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
}) {
  // Haptic mirrors intent: error = warn, success = confirm, info = tap.
  if (isError) {
    HapticFeedback.vibrate();
  } else if (isSuccess) {
    HapticFeedback.mediumImpact();
  } else {
    HapticFeedback.selectionClick();
  }

  final accent = isError
      ? HavenColors.expired
      : isSuccess
          ? HavenColors.active
          : HavenColors.primary;
  final icon = isError
      ? Icons.error_outline
      : isSuccess
          ? Icons.check_circle_outline
          : Icons.info_outline;

  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: duration,
      backgroundColor: HavenColors.elevated,
      margin: const EdgeInsets.all(HavenSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HavenRadius.button),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      content: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: HavenSpacing.sm),
          Expanded(
            child: Text(message, style: HavenText.body),
          ),
        ],
      ),
      action: action,
    ),
  );
}
