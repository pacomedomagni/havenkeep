import 'package:flutter/material.dart';
import 'theme.dart';

/// Shows a confirmation dialog styled with the HavenKeep design system.
///
/// Returns `true` if the user taps the confirm action, and `false` if they
/// cancel or dismiss the dialog. When [isDestructive] is true the confirm
/// button uses a red (expired) colour to signal danger.
///
/// ```dart
/// final confirmed = await showHavenConfirmDialog(
///   context,
///   title: 'Delete item?',
///   body: 'This action cannot be undone.',
///   confirmLabel: 'Delete',
///   isDestructive: true,
/// );
/// ```
Future<bool> showHavenConfirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final theme = Theme.of(dialogContext);

      return AlertDialog(
        backgroundColor: HavenColors.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HavenRadius.card),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleLarge,
        ),
        content: body != null
            ? Text(
                body,
                style: theme.textTheme.bodyMedium,
              )
            : null,
        actions: [
          // Cancel button
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: HavenColors.textSecondary,
            ),
            child: Text(cancelLabel),
          ),
          // Confirm button
          if (isDestructive)
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: HavenColors.expired,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HavenRadius.button),
                ),
              ),
              child: Text(confirmLabel),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: HavenColors.primary,
              ),
              child: Text(confirmLabel),
            ),
        ],
      );
    },
  );

  return result ?? false;
}
