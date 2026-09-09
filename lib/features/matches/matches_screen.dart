import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../chat/chat_screen.dart';
import '../chat/data/messages_providers.dart';
import 'data/match_model.dart';
import 'data/matches_providers.dart';

/// Surfaces candidate matches from `my_matches()` — populated automatically
/// by the `record_matches_for_image` trigger whenever a photo with an
/// embedding is uploaded (see Phase 5 in the README). Tapping a verdict
/// button updates `matches.status`; there's no chat/claim flow wired to a
/// "confirmed" match yet — that's Phases 7–8.
class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Matches for you')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(matchesProvider.future),
        child: matchesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _EmptyState(
            icon: Icons.error_outline,
            title: "Couldn't load matches",
            body: 'Check your connection and pull down to try again.',
          ),
          data: (matches) {
            final pending = matches.where((m) => m.status == 'pending').toList();
            final decided = matches.where((m) => m.status != 'pending').toList();

            if (matches.isEmpty) {
              return _EmptyState(
                icon: Icons.auto_awesome_outlined,
                title: 'No matches yet',
                body: 'Once you report a lost or found item, our on-device AI '
                    "compares its photo against everyone else's to look for a "
                    "possible match — they'll show up here automatically.",
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (pending.isNotEmpty) ...[
                  Text('Needs your input', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final match in pending) ...[
                    _MatchCard(match: match),
                    const SizedBox(height: 12),
                  ],
                ],
                if (decided.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Already decided', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final match in decided) ...[
                    _MatchCard(match: match),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MatchCard extends ConsumerWidget {
  const _MatchCard({required this.match});

  final MatchModel match;

  Future<void> _act(WidgetRef ref, BuildContext context, String status) async {
    try {
      await ref.read(matchesRepositoryProvider).updateStatus(match.matchId, status);
      ref.invalidate(matchesProvider);
      if (status == 'confirmed') {
        // A confirmed match is exactly what makes it show up in
        // my_conversations(), so the chat list needs to know too.
        ref.invalidate(conversationsProvider);
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update this match. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColor =
        match.matchedItemIsLost ? theme.colorScheme.error : theme.colorScheme.tertiary;
    final isPending = match.status == 'pending';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: match.matchedItemImageUrl == null
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.image_outlined,
                                color: theme.colorScheme.onSurfaceVariant),
                          )
                        : CachedNetworkImage(
                            imageUrl: match.matchedItemImageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: theme.colorScheme.surfaceContainerHighest),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              match.matchedItemIsLost ? 'LOST' : 'FOUND',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(match.similarityScore * 100).round()}% match',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(match.matchedItemTitle, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        'Compared with your "${match.myItemTitle}" · '
                        '${DateFormat.MMMd().format(match.createdAt)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _act(ref, context, 'dismissed'),
                      child: const Text('Not a match'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _act(ref, context, 'confirmed'),
                      child: const Text('This is it!'),
                    ),
                  ),
                ],
              ),
            ] else if (match.status == 'confirmed') ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.push(
                  '/chat',
                  extra: ChatScreenArgs(
                    matchId: match.matchId,
                    otherUserId: match.matchedItemUserId,
                    otherItemTitle: match.matchedItemTitle,
                    myItemId: match.myItemId,
                    matchedItemId: match.matchedItemId,
                    matchedItemType: match.matchedItemType,
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Message'),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Dismissed',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    child: Icon(icon, size: 40, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 20),
                  Text(title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    body,
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
