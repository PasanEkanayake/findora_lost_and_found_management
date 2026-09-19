import 'package:flutter/material.dart';

/// How long a post is considered "new" — tunable in one place since it's
/// used both to decide whether to render [NewBadge] and, indirectly,
/// governs how long that badge stays visible before it just stops
/// appearing on its own (there's no timer to cancel or job to run: every
/// build re-checks the item's age against this window, so the badge
/// disappears the next time the surrounding list happens to rebuild after
/// the window has passed — pull-to-refresh, reopening the app, etc.).
const Duration newPostWindow = Duration(days: 3);

bool isRecentlyPosted(DateTime createdAt) {
  return DateTime.now().difference(createdAt) < newPostWindow;
}

/// A small "NEW" pill — deliberately a distinct color (the brand's orange
/// secondary) from the LOST (red/error) and FOUND (teal/tertiary) badges
/// it sits next to, so it reads as an separate, temporary annotation
/// rather than another status.
class NewBadge extends StatelessWidget {
  const NewBadge({super.key, this.dense = false});

  /// Slightly smaller padding/text for tight spaces (list cards) vs the
  /// full size used on the item detail screen.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_new_rounded, size: dense ? 13 : 15, color: theme.colorScheme.secondary),
          SizedBox(width: dense ? 2 : 3),
          Text(
            'NEW',
            style: (dense ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)?.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
