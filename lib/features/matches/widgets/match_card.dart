import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../chat/chat_screen.dart';
import '../../../core/widgets/item_photo.dart';
import '../data/match_model.dart';
import '../data/matches_providers.dart';
import '../../chat/data/messages_providers.dart';

/// One match, shown as a card: the headline score, "your item" vs "possible
/// match" side by side (each tappable to open that post), the score
/// breakdown, and — depending on [MatchModel.status] — either Confirm/Not a
/// match buttons or a Message button. Shared between [MatchesScreen] (every
/// match for the signed-in user) and a single post's own matches list, so a
/// match looks and behaves identically everywhere it appears.
///
/// **Always pass `key: ValueKey(match.matchId)`** wherever more than one
/// card is rendered in the same list (MatchesScreen, ItemMatchesScreen).
/// Confirming or dismissing a pending match moves it to a different
/// section of that list on the very next rebuild — without a stable key,
/// Flutter can't tell "this card's match changed" from "a card at this
/// position now represents a different match", and can reuse this card's
/// Element (mid-flight async work and all) for what is, from the data's
/// point of view, a completely different match. That mismatch is a
/// plausible cause of framework-level tree-consistency crashes seen after
/// tapping "This is it!" — the fix is this key, not a try/catch, since the
/// framework corruption happens beneath what Dart exceptions can catch.
class MatchCard extends ConsumerWidget {
  /// [key] should always be given as `ValueKey(match.matchId)` by callers
  /// that render more than one of these in a list — see the class doc.
  const MatchCard({super.key, required this.match});

  final MatchModel match;

  Future<void> _act(WidgetRef ref, BuildContext context, String status) async {
    try {
      await ref.read(matchesRepositoryProvider).updateStatus(match.matchId, status);
      if (!context.mounted) return;
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
    final isPending = match.status == 'pending';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Headline: how strong the match is, and when it was found.
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '${(match.similarityScore * 100).round()}% match',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat.MMMd().format(match.createdAt),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // The two items side by side: yours on the left, the one it was
            // matched with on the right. Either can be tapped to open the
            // full post.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MatchSide(
                    caption: 'YOUR ITEM',
                    isLost: match.myItemIsLost,
                    title: match.myItemTitle,
                    imageUrl: match.myItemImageUrl,
                    highlight: true,
                    onTap: () => context.push('/item/${match.myItemId}'),
                  ),
                ),
                Padding(
                  // Roughly level with the middle of the two photos.
                  padding: const EdgeInsets.fromLTRB(6, 72, 6, 0),
                  child: Icon(
                    Icons.compare_arrows,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: _MatchSide(
                    caption: 'POSSIBLE MATCH',
                    isLost: match.matchedItemIsLost,
                    title: match.matchedItemTitle,
                    imageUrl: match.matchedItemImageUrl,
                    onTap: () => context.push('/item/${match.matchedItemId}'),
                  ),
                ),
              ],
            ),
            if (match.imageSimilarity != null ||
                match.textSimilarity != null ||
                match.distanceMeters != null ||
                match.timeProximity != null) ...[
              const SizedBox(height: 10),
              _ScoreBreakdown(match: match),
            ],
            const SizedBox(height: 4),
            Text(
              'Tap either item to view its post.',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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

/// One of the two items on a match card: photo, which side it is ("YOUR
/// ITEM" / "POSSIBLE MATCH"), lost-or-found, and title. Tapping opens the
/// full post.
class _MatchSide extends StatelessWidget {
  const _MatchSide({
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

  /// Marks "your" side with a coloured outline so the two sides are easy to
  /// tell apart at a glance.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = isLost ? theme.colorScheme.error : theme.colorScheme.tertiary;

    return Semantics(
      button: true,
      label: '$caption: $title, ${isLost ? 'lost' : 'found'}. Opens the post.',
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
                style: theme.textTheme.labelSmall?.copyWith(
                  color: highlight
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ItemPhoto(url: imageUrl),
                ),
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
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: typeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "📷 92% · 📝 78% · 📍 1.2 km · 🕐 6h apart" — the ingredients behind the
/// headline "XX% match" figure, shown only for whichever signals this
/// particular pair actually has (see MatchModel's doc on why each is
/// independently nullable). Distance and time are shown in real units
/// rather than as another percentage each, since "1.2 km apart"/"6h apart"
/// are more immediately meaningful than a raw proximity score would be on
/// its own.
class _ScoreBreakdown extends StatelessWidget {
  const _ScoreBreakdown({required this.match});

  final MatchModel match;

  /// time_proximity_score() is exp(-hours_apart / 72) — inverted here to
  /// recover an approximate hours-apart figure for display, since that's
  /// what a person actually wants to read ("6h apart"), not the 0..1
  /// score itself.
  String _approxHoursApartLabel(double timeProximity) {
    if (timeProximity <= 0) return 'days apart';
    final hoursApart = -72 * math.log(timeProximity);
    if (hoursApart < 1) return '<1h apart';
    if (hoursApart < 48) return '${hoursApart.round()}h apart';
    return '${(hoursApart / 24).round()}d apart';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];

    if (match.imageSimilarity != null) {
      parts.add('📷 ${(match.imageSimilarity! * 100).round()}%');
    }
    if (match.textSimilarity != null) {
      parts.add('📝 ${(match.textSimilarity! * 100).round()}%');
    }
    if (match.distanceMeters != null) {
      final km = match.distanceMeters! / 1000;
      parts.add(km < 1 ? '📍 ${match.distanceMeters!.round()} m' : '📍 ${km.toStringAsFixed(1)} km');
    }
    if (match.timeProximity != null) {
      parts.add('🕐 ${_approxHoursApartLabel(match.timeProximity!)}');
    }

    return Text(
      parts.join('  ·  '),
      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

