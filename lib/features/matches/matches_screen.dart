import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../items/data/items_providers.dart';
import '../../core/ml/tflite_classifier.dart';
import '../../core/ml/tflite_provider.dart';
import '../../core/widgets/shimmer_list.dart';
import 'data/match_model.dart';
import 'data/matches_providers.dart';
import 'widgets/match_card.dart';

/// Narrows the match list by which signal(s) actually contributed to it.
///
/// [imageOnly]/[textOnly]/[both] didn't always make sense as separate
/// options: before `supabase/12_text_matching.sql`, every match had to
/// pass the image threshold just to exist as a candidate at all (see
/// `matching_threshold()`), so "only image" and "both" would have been
/// identical and "only text" would always have been empty. Text matching
/// now finds pairs with no photo involved at all, so a match's
/// `imageSimilarity`/`textSimilarity` can each independently be present or
/// null — these three options are how to tell those cases apart.
enum _MatchFilter { all, imageOnly, textOnly, both, nearby, time }

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
    final hasImage = match.imageSimilarity != null;
    final hasText = match.textSimilarity != null && match.textSimilarity! >= 0.5;
    switch (_filter) {
      case _MatchFilter.all:
        return true;
      case _MatchFilter.imageOnly:
        return hasImage && !hasText;
      case _MatchFilter.textOnly:
        return hasText && !hasImage;
      case _MatchFilter.both:
        return hasImage && hasText;
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

  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    // Quietly catches up any of this user's photos that never got an AI
    // embedding (posted before the model worked, or while it failed) —
    // those photos are invisible to matching until they have one. Runs
    // once per visit to this tab and says nothing if there's nothing to do.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scan(manual: false);
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? theme.colorScheme.error : null,
        duration: Duration(seconds: isError ? 8 : 4),
      ),
    );
  }

  Future<TfliteClassifier?> _loadClassifierOrExplain() async {
    try {
      return await ref.read(tfliteClassifierProvider.future);
    } catch (e) {
      _showSnack(
        "The on-device AI model couldn't load: $e\n"
        'Check that assets/models/ has both files, then fully restart the app '
        '(stop + flutter run — hot reload does not reload assets).',
        isError: true,
      );
      return null;
    }
  }

  /// Embeds this user's own photos that are missing an embedding. Each one
  /// that succeeds makes the database run the match search for it (see
  /// ItemsRepository.embedExistingImage), so new matches can appear
  /// straight after — hence the refetch at the end.
  ///
  /// [manual] is true when the person tapped the scan button: only then is
  /// a "nothing to do" outcome worth announcing. Failures are always
  /// announced — the whole reason this exists is that AI matching used to
  /// fail without anyone being told.
  Future<void> _scan({required bool manual}) async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    try {
      final repo = ref.read(itemsRepositoryProvider);
      final pending = await repo.fetchMyImagesMissingEmbeddings();
      if (pending.isEmpty) {
        if (manual) {
          _showSnack(
            'Your photos are all analysed. A match also needs the other '
            "person's photo to be analysed — that happens when they open "
            'the updated app.',
          );
        }
        return;
      }

      final classifier = await _loadClassifierOrExplain();
      if (classifier == null) return;

      var done = 0;
      var failed = 0;
      String? firstError;
      for (final image in pending) {
        try {
          await repo.embedExistingImage(
            imageId: image.id,
            imageUrl: image.url,
            classifier: classifier,
          );
          done++;
        } catch (e) {
          failed++;
          firstError ??= '$e';
        }
      }

      if (!mounted) return;
      ref.invalidate(matchesProvider);
      if (failed == 0) {
        _showSnack('Scanned $done photo${done == 1 ? '' : 's'} — checking for matches.');
      } else {
        _showSnack(
          'Scanned $done, failed $failed. First error: $firstError',
          isError: true,
        );
      }
    } catch (e) {
      _showSnack("Couldn't scan your photos: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matchesAsync = ref.watch(matchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matches for you'),
        actions: [
          IconButton(
            icon: const Icon(Icons.image_search),
            tooltip: 'Scan my photos for matches',
            onPressed: _isScanning ? null : () => _scan(manual: true),
          ),
        ],
        bottom: _isScanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
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
                    "possible match — they'll show up here automatically. "
                    'Posted before? Tap the scan icon (top right) to re-check '
                    'your photos.',
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
                          label: '📷 Image only',
                          selected: _filter == _MatchFilter.imageOnly,
                          onTap: () => setState(() => _filter = _MatchFilter.imageOnly),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: '📝 Text only',
                          selected: _filter == _MatchFilter.textOnly,
                          onTap: () => setState(() => _filter = _MatchFilter.textOnly),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: '📷📝 Both',
                          selected: _filter == _MatchFilter.both,
                          onTap: () => setState(() => _filter = _MatchFilter.both),
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
                                MatchCard(key: ValueKey(match.matchId), match: match),
                                const SizedBox(height: 12),
                              ],
                            ],
                            if (decided.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text('Already decided',
                                  style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 8),
                              for (final match in decided) ...[
                                MatchCard(key: ValueKey(match.matchId), match: match),
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
