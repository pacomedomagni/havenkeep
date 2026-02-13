import 'package:flutter/material.dart';
import 'theme.dart';

/// Consistent snackbar helper for HavenKeep.
///
/// All snackbars use floating behavior and consistent styling.
void showHavenSnackBar(
  BuildContext context, {
  required String message,
  bool isError = false,
  bool isSuccess = false,
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
}) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: duration,
      backgroundColor: isError
          ? HavenColors.expired
          : isSuccess
              ? HavenColors.active
              : null,
      action: action,
    ),
  );
}
