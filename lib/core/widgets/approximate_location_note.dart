import 'package:flutter/material.dart';

/// One line under a "set location" control: others only ever see an
/// approximate area, never the exact spot. See
/// supabase/33_approximate_locations.sql.
class ApproximateLocationNote extends StatelessWidget {
  const ApproximateLocationNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Other people only see an approximate area (about 500 m) — '
              'never the exact spot or the street.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
