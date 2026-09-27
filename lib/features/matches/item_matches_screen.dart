import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/auth_providers.dart';
import '../items/data/items_providers.dart';
import 'data/matches_providers.dart';
import 'widgets/match_card.dart';

/// Every match involving one specific post — reached from that post's
/// detail screen ("View possible matches"). A thin filter over
/// [matchesProvider] (every match for the signed-in user) rather than its
/// own query, so a decision made here (Confirm / Not a match / Message)
/// shows up immediately in the main Matches tab too, and vice versa.
///
/// [itemId] can be either side of a match: the signed-in user's own post,
/// or someone else's post that already matched against one of the user's
/// own — both cases just filter to whichever rows mention this id.
class ItemMatchesScreen extends ConsumerWidget {
  const ItemMatchesScreen({super.key, required this.itemId, this.itemTitle});

  final String itemId;

  /// Shown as a subtitle under the app bar title, when the caller already
  /// has it handy — [ItemDetailScreen] always does, since it's already
  /// showing this post. Optional rather than looked up here again because
  /// a match row only carries the *other* item's title, not this one's.
  final String? itemTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Possible matches'),
            if (itemTitle != null)
              Text(
                itemTitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.7),
                    ),
              ),
          ],
        ),
      ),
      body: matchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "Couldn't load matches. Pull down on the Matches tab to try again.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
        data: (matches) {
          final relevant = matches
              .where((m) => m.myItemId == itemId || m.matchedItemId == itemId)
              .toList();

          if (relevant.isEmpty) {
            return _EmptyState(itemId: itemId);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              for (final match in relevant) ...[
                MatchCard(key: ValueKey(match.matchId), match: match),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Shown when this post currently has no matches. Distinguishes "you own
/// this post, so a scan/wait might still turn one up" from "nothing
/// currently connects this post to one of your own" — the second case
/// only reaches this screen at all if a match existed a moment ago and was
/// just dismissed, since [ItemDetailScreen] only offers this screen when
/// there's something to show.
class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final myItemAsync = ref.watch(itemDetailProvider(itemId));
    final myId = ref.watch(currentUserProvider)?.id;
    final isMine = myItemAsync.maybeWhen(
      data: (item) => myId != null && item.userId == myId,
      orElse: () => false,
    );

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
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
                  Text('No matches for this post', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    isMine
                        ? 'The AI compares this post automatically — its title and '
                            "description always, its photo too if it has one. If you "
                            'just posted or just added a photo, check back in a '
                            'moment, or open the Matches tab and tap the scan icon.'
                        : "This post isn't currently matched with any of your own posts.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
