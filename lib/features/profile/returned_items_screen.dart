import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/item_photo.dart';
import '../../core/widgets/star_rating.dart';
import '../chat/chat_screen.dart';
import '../items/data/items_providers.dart';
import '../items/data/returned_item_model.dart';

/// Profile → Returned items. Every post of the signed-in user's that was
/// handed back, next to the post it was returned with.
///
/// Both posts of a returned pair are hidden from everyone but their two
/// owners (see supabase/13_returned_items_and_ratings.sql), so this list is
/// the only place either of them can still be found.
class ReturnedItemsScreen extends ConsumerWidget {
  const ReturnedItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final returnedAsync = ref.watch(returnedItemsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Returned items')),
      body: returnedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Couldn't load your returned items.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(returnedItemsProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (items) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(returnedItemsProvider);
            await ref.read(returnedItemsProvider.future);
          },
          child: ListView(
            // Always scrollable so pull-to-refresh works on a short or empty list.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Once an item is returned, both posts are hidden from everyone '
                        'else so they can\'t confuse other people\'s matches. Only you and '
                        'the person you returned it with can see them here.',
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
                  child: Column(
                    children: [
                      Icon(Icons.task_alt, size: 48, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text('Nothing returned yet', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        "When you get an item back — or hand one back — it will appear "
                        "here once it's marked as returned.",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else
                for (final item in items) ...[
                  _ReturnedCard(key: ValueKey(item.myItemId), item: item),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReturnedCard extends StatelessWidget {
  const _ReturnedCard({super.key, required this.item});

  final ReturnedItemModel item;

  void _openChat(BuildContext context) {
    context.push(
      '/chat',
      extra: ChatScreenArgs(
        matchId: item.matchId!,
        otherUserId: item.otherUserId!,
        otherItemTitle: item.otherItemTitle!,
        myItemId: item.myItemId,
        matchedItemId: item.otherItemId!,
        matchedItemType: item.otherItemType!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.task_alt, size: 18, color: theme.colorScheme.tertiary),
                const SizedBox(width: 6),
                Text(
                  'Returned ${DateFormat.yMMMd().format(item.resolvedAt)}',
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.tertiary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PostTile(
                    caption: 'YOUR POST',
                    isLost: item.myItemType == 'lost',
                    title: item.myItemTitle,
                    imageUrl: item.myItemImageUrl,
                    highlight: true,
                    onTap: () => context.push('/item/${item.myItemId}'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 72, 6, 0),
                  child: Icon(Icons.swap_horiz, color: theme.colorScheme.onSurfaceVariant),
                ),
                Expanded(
                  child: item.hasCounterpart
                      ? _PostTile(
                          caption: 'RETURNED WITH ${item.otherUserName.toUpperCase()}',
                          isLost: item.otherItemType == 'lost',
                          title: item.otherItemTitle ?? 'Post',
                          imageUrl: item.otherItemImageUrl,
                          onTap: () => context.push('/item/${item.otherItemId}'),
                        )
                      : const _MissingCounterpart(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _RatingLine(
              label: 'You rated ${item.otherUserName}',
              stars: item.starsIGave,
              emptyText: item.hasCounterpart ? 'Not rated yet' : 'No rating',
            ),
            const SizedBox(height: 4),
            _RatingLine(
              label: '${item.otherUserName} rated you',
              stars: item.starsIReceived,
              emptyText: 'Not rated yet',
            ),
            if (item.canOpenChat) ...[
              const SizedBox(height: 12),
              if (!item.iHaveRated)
                FilledButton.icon(
                  onPressed: () => _openChat(context),
                  icon: const Icon(Icons.star_outline_rounded),
                  label: Text('Rate ${item.otherUserName}'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => _openChat(context),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Open chat'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({
    required this.caption,
    required this.isLost,
    required this.title,
    required this.imageUrl,
    required this.onTap,
    this.highlight = false,
  });

  final String caption;
  final bool isLost;
  final String title;
  final String? imageUrl;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = isLost ? theme.colorScheme.error : theme.colorScheme.tertiary;

    return Semantics(
      button: true,
      label: '$caption: $title, ${isLost ? 'lost' : 'found'}. Opens the post.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlight ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
              width: highlight ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: highlight ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(aspectRatio: 1, child: ItemPhoto(url: imageUrl)),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isLost ? 'LOST' : 'FOUND',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: typeColor, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown for a post returned before the other side was being recorded.
class _MissingCounterpart extends StatelessWidget {
  const _MissingCounterpart();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        "The other post isn't available for this older return.",
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.label, required this.stars, required this.emptyText});

  final String label;
  final int? stars;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        if (stars != null)
          StarRating(rating: stars!.toDouble(), size: 16)
        else
          Text(
            emptyText,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
