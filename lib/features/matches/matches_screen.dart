import 'package:flutter/material.dart';

/// Surfaces candidate matches from the `matches` table (populated by the
/// `match_items` pgvector RPC — see Phase 5). Shown here as an empty state
/// since there's no real data until items with photos exist.
class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Matches for you')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 40,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text('No matches yet', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Once you report a lost or found item, our on-device AI '
                "compares its photo against everyone else's to look for a "
                "possible match — they'll show up here automatically.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
