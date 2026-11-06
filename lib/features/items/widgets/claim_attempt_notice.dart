import 'package:flutter/material.dart';

/// The attempt warning at the top of the "File a claim" form: calm for
/// "Attempt 2 of 3", red and bold for the last attempt.
class ClaimAttemptNotice extends StatelessWidget {
  const ClaimAttemptNotice({super.key, required this.message, this.urgent = false});

  final String message;

  /// The final attempt — shown as a warning.
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background =
        urgent ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer;
    final foreground =
        urgent ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSecondaryContainer;
    return Semantics(
      liveRegion: urgent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              urgent ? Icons.warning_amber_rounded : Icons.info_outline,
              size: 20,
              color: foreground,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground,
                  fontWeight: urgent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
