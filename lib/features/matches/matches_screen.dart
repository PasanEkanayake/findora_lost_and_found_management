import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../chat/chat_screen.dart';
import '../chat/data/messages_providers.dart';
import '../../core/widgets/shimmer_list.dart';
import 'data/match_model.dart';
import 'data/matches_providers.dart';

/// Which of the non-mandatory signals a match must have a meaningful
/// value for, to narrow the list down. Image similarity isn't one of the
/// options here on purpose: every match already passed the 0.75 image
/// threshold just to exist as a candidate at all (see match_items() in
/// supabase/10_open_matching_and_time.sql), so filtering by "has an image
/// match" would never actually exclude anything.
enum _MatchFilter { all, text, nearby, time }

/// Surfaces candidate matches from `my_matches()` — populated automatically
/// by the `record_matches_for_image` trigger whenever a photo with an
/// embedding is uploaded (see Phase 5 in the README, and
/// supabase/10_open_matching_and_time.sql for the current scoring). Tapping
/// a verdict button updates `matches.status`.
class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({super.key});

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  _MatchFilter _filter = _MatchFilter.all;

  bool _passesFilter(MatchModel match) {
    switch (_filter) {
      case _MatchFilter.all:
        return true;
      case _MatchFilter.text:
        return match.textSimilarity != null && match.textSimilarity! >= 0.5;
      case _MatchFilter.nearby:
        // 5km, matching the map view's default search radius elsewhere
        // in the app — "nearby" means the same thing in both places.
        return match.distanceMeters != null && match.distanceMeters! <= 5000;
      case _MatchFilter.time:
        // 0.5 on time_proximity_score's 72-hour decay works out to
        // roughly two days apart or closer — see that function's doc.
        return match.timeProximity != null && match.timeProximity! >= 0.5;
    }
  }

  @override
  Widget build(BuildContext context) {
    final matchesAsync = ref.watch(matchesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Matches for you')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(matchesProvider.future),
        child: matchesAsync.when(
          loading: () => const ShimmerCardList(),
          error: (error, _) => _EmptyState(
            icon: Icons.error_outline,
            title: "Couldn't load matches",
            body: 'Check your connection and pull down to try again.',
          ),
          data: (allMatches) {
            if (allMatches.isEmpty) {
              return _EmptyState(
                icon: Icons.auto_awesome_outlined,
                title: 'No matches yet',
                body: 'Once you report a lost or found item, our on-device AI '
                    "compares its photo against everyone else's to look for a "
                    "possible match — they'll show up here automatically.",
              );
            }

            final matches = allMatches.where(_passesFilter).toList();
            final pending = matches.where((m) => m.status == 'pending').toList();
            final decided = matches.where((m) => m.status != 'pending').toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _FilterChip(
                          label: 'All',
                          selected: _filter == _MatchFilter.all,
                          onTap: () => setState(() => _filter = _MatchFilter.all),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: '📝 Text match',
                          selected: _filter == _MatchFilter.text,
                          onTap: () => setState(() => _filter = _MatchFilter.text),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: '📍 Nearby',
                          selected: _filter == _MatchFilter.nearby,
                          onTap: () => setState(() => _filter = _MatchFilter.nearby),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: '🕐 Similar time',
                          selected: _filter == _MatchFilter.time,
                          onTap: () => setState(() => _filter = _MatchFilter.time),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: matches.isEmpty
                      ? _EmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          title: 'No matches with this filter',
                          body: 'Try a different filter, or "All" to see every match again.',
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            if (pending.isNotEmpty) ...[
                              Text('Needs your input',
                                  style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 8),
                              for (final match in pending) ...[
                                _MatchCard(match: match),
                                const SizedBox(height: 12),
                              ],
                            ],
                            if (decided.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text('Already decided',
                                  style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 8),
                              for (final match in decided) ...[
                                _MatchCard(match: match),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
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
                      if (match.imageSimilarity != null ||
                          match.textSimilarity != null ||
                          match.distanceMeters != null ||
                          match.timeProximity != null) ...[
                        const SizedBox(height: 4),
                        _ScoreBreakdown(match: match),
                      ],
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
