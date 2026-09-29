import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/star_rating.dart';
import 'data/profile_providers.dart';
import 'data/rating_model.dart';

/// Profile → Ratings & reviews. Reviews the signed-in user has **received**
/// (with an average and star breakdown) and ones they have **given**.
///
/// Only the two people involved in a rating can read it — the database
/// enforces that (supabase/13_returned_items_and_ratings.sql); this screen
/// simply shows what `my_ratings()` returns.
class RatingsScreen extends ConsumerWidget {
  const RatingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingsAsync = ref.watch(myRatingsProvider);

    return ratingsAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Ratings & reviews')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Ratings & reviews')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Couldn't load your ratings.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(myRatingsProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (ratings) {
        final received = ratings.where((r) => r.isReceived).toList();
        final given = ratings.where((r) => !r.isReceived).toList();

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Ratings & reviews'),
              bottom: TabBar(
                tabs: [
                  Tab(text: 'Received (${received.length})'),
                  Tab(text: 'Given (${given.length})'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _RatingsList(
                  ratings: received,
                  header: received.isEmpty ? null : _SummaryCard(ratings: received),
                  emptyTitle: 'No ratings yet',
                  emptyBody: 'After an item is returned, you and the other person can '
                      'rate each other. Ratings you receive will show up here.',
                  onRefresh: () async {
                    ref.invalidate(myRatingsProvider);
                    await ref.read(myRatingsProvider.future);
                  },
                ),
                _RatingsList(
                  ratings: given,
                  emptyTitle: "You haven't rated anyone yet",
                  emptyBody: 'Once an item has been returned, open Profile → Returned '
                      'items to rate the other person.',
                  onRefresh: () async {
                    ref.invalidate(myRatingsProvider);
                    await ref.read(myRatingsProvider.future);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RatingsList extends StatelessWidget {
  const _RatingsList({
    required this.ratings,
    required this.emptyTitle,
    required this.emptyBody,
    required this.onRefresh,
    this.header,
  });

  final List<RatingModel> ratings;
  final Widget? header;
  final String emptyTitle;
  final String emptyBody;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (header != null) ...[header!, const SizedBox(height: 16)],
          if (ratings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              child: Column(
                children: [
                  Icon(Icons.star_outline_rounded,
                      size: 48, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(emptyTitle, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    emptyBody,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            for (final rating in ratings) ...[
              _ReviewCard(key: ValueKey(rating.id), rating: rating),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

/// Average, count and a 5→1 star breakdown, computed from the reviews the
/// user has received.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.ratings});

  final List<RatingModel> ratings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = ratings.length;
    final average = ratings.fold<int>(0, (sum, r) => sum + r.stars) / total;
    final counts = <int, int>{for (var s = 1; s <= 5; s++) s: 0};
    for (final r in ratings) {
      counts[r.stars] = (counts[r.stars] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  average.toStringAsFixed(1),
                  style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                StarRating(rating: average, size: 18),
                const SizedBox(height: 4),
                Text(
                  '$total rating${total == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                children: [
                  for (var s = 5; s >= 1; s--)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Semantics(
                        label: '$s star: ${counts[s]} of $total',
                        excludeSemantics: true,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              child: Text('$s', style: theme.textTheme.labelSmall),
                            ),
                            Icon(Icons.star_rounded, size: 12, color: theme.colorScheme.secondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (counts[s] ?? 0) / total,
                                  minHeight: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${counts[s]}',
                                textAlign: TextAlign.end,
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({super.key, required this.rating});

  final RatingModel rating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = rating.isReceived ? rating.otherUserName : 'You rated ${rating.otherUserName}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StarRating(rating: rating.stars.toDouble(), size: 18),
                const Spacer(),
                Text(
                  DateFormat.yMMMd().format(rating.createdAt),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              rating.comment ?? 'No written comment.',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
                fontStyle: rating.comment == null ? FontStyle.italic : FontStyle.normal,
                color: rating.comment == null ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              rating.itemTitle == null ? who : '$who · ${rating.itemTitle}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
