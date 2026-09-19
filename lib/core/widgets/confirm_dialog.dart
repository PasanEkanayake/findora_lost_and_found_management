import 'package:flutter/material.dart';

/// A single reusable "are you sure?" dialog, used anywhere a destructive or
/// otherwise hard-to-undo action (deleting a post, leaving the app) needs a
/// confirmation step — kept in one place so every confirmation in the app
/// looks and behaves the same way instead of each screen rolling its own.
///
/// Returns `true` only if the person tapped [confirmLabel]; `false` or
/// `null` (dismissed by tapping outside/back) both mean "don't proceed".
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
  IconData? icon,
}) async {
  final theme = Theme.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: icon != null
          ? Icon(
              icon,
              color: isDestructive ? theme.colorScheme.error : theme.colorScheme.primary,
              size: 32,
            )
          : null,
      title: Text(title, textAlign: icon != null ? TextAlign.center : TextAlign.start),
      content: Text(message, textAlign: icon != null ? TextAlign.center : TextAlign.start),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        isDestructive
            ? FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmLabel),
              )
            : FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmLabel),
              ),
      ],
    ),
  );
  return result ?? false;
}
