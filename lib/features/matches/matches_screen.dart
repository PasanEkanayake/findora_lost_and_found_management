import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/data/safety_providers.dart';
import '../items/data/items_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../core/ml/tflite_classifier.dart';
import '../../core/ml/tflite_provider.dart';
import '../../core/paging/page_result.dart';
import '../../core/widgets/shimmer_list.dart';
import '../../core/widgets/show_more_button.dart';
import 'data/match_model.dart';
import 'data/matches_providers.dart';
import 'widgets/match_card.dart';
import 'widgets/match_legend.dart';

/// Surfaces candidate matches from `my_matches_page()` — populated automatically
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
  /// Which signal(s) a match must have — sent to the server, which filters
  /// before paging (see supabase/29_matches_paging.sql).
  MatchFilter _filter = MatchFilter.all;

  // The two sections are paged separately. Each grows by [kListPageSize] per
  // "Show more"; a refresh re-reads the same number of rows, so the lists
  // never collapse back to the first page on their own.
  int _pendingLimit = kListPageSize;
  int _waitingLimit = kListPageSize;
  int _decidedLimit = kListPageSize;

  /// Last data shown for each section, so the list stays on screen (with a
  /// spinner on its button) while a bigger page loads.
  PageResult<MatchModel>? _lastPending;
  PageResult<MatchModel>? _lastWaiting;
  PageResult<MatchModel>? _lastDecided;

  /// Back to the first page of everything. Call inside setState.
  void _resetPaging({bool forgetShown = false}) {
    _pendingLimit = kListPageSize;
    _waitingLimit = kListPageSize;
    _decidedLimit = kListPageSize;
    if (forgetShown) {
      _lastPending = null;
      _lastWaiting = null;
      _lastDecided = null;
    }
  }

  void _setFilter(MatchFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _resetPaging(forgetShown: true);
    });
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
    final pendingAsync = ref.watch(matchesProvider(
      MatchesQuery(section: 'pending', filter: _filter, limit: _pendingLimit),
    ));
    final waitingAsync = ref.watch(matchesProvider(
      MatchesQuery(section: 'waiting', filter: _filter, limit: _waitingLimit),
    ));
    final decidedAsync = ref.watch(matchesProvider(
      MatchesQuery(section: 'decided', filter: _filter, limit: _decidedLimit),
    ));
    // While a bigger page loads, keep showing what was there.
    final pendingPage = pendingAsync.value ?? _lastPending;
    final waitingPage = waitingAsync.value ?? _lastWaiting;
    final decidedPage = decidedAsync.value ?? _lastDecided;
    _lastPending = pendingPage;
    _lastWaiting = waitingPage;
    _lastDecided = decidedPage;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).matchesTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'What do the match labels mean?',
            onPressed: () => showMatchLegendSheet(context),
          ),
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
        onRefresh: () async {
          setState(_resetPaging);
          ref.invalidate(matchesProvider);
          try {
            await ref.read(
              matchesProvider(MatchesQuery(section: 'pending', filter: _filter)).future,
            );
          } catch (_) {
            // The error state on screen says it; the spinner just stops.
          }
        },
        child: Builder(builder: (context) {
          if (pendingPage == null || waitingPage == null || decidedPage == null) {
            if (pendingAsync.hasError || waitingAsync.hasError || decidedAsync.hasError) {
              return _EmptyState(
                icon: Icons.error_outline,
                title: AppLocalizations.of(context).matchesLoadErrorTitle,
                body: AppLocalizations.of(context).matchesLoadErrorBody,
              );
            }
            return const ShimmerCardList();
          }

          // Matches with someone I've blocked are hidden too (the server
          // already leaves them out; this makes a just-made block instant).
          final blocked = ref.watch(blockedUserIdsProvider).value ?? const <String>{};
          final pending = pendingPage.items
              .where((m) => !blocked.contains(m.matchedItemUserId))
              .toList();
          final waiting = waitingPage.items
              .where((m) => !blocked.contains(m.matchedItemUserId))
              .toList();
          final decided = decidedPage.items
              .where((m) => !blocked.contains(m.matchedItemUserId))
              .toList();

          if (pending.isEmpty && waiting.isEmpty && decided.isEmpty && _filter == MatchFilter.all) {
            return _EmptyState(
              icon: Icons.auto_awesome_outlined,
              title: AppLocalizations.of(context).matchesEmptyTitle,
              body: AppLocalizations.of(context).matchesEmptyBody,
            );
          }

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
                        label: AppLocalizations.of(context).matchFilterAll,
                        selected: _filter == MatchFilter.all,
                        onTap: () => _setFilter(MatchFilter.all),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: AppLocalizations.of(context).matchFilterImageOnly,
                        selected: _filter == MatchFilter.imageOnly,
                        onTap: () => _setFilter(MatchFilter.imageOnly),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: AppLocalizations.of(context).matchFilterTextOnly,
                        selected: _filter == MatchFilter.textOnly,
                        onTap: () => _setFilter(MatchFilter.textOnly),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: AppLocalizations.of(context).matchFilterBoth,
                        selected: _filter == MatchFilter.both,
                        onTap: () => _setFilter(MatchFilter.both),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: AppLocalizations.of(context).matchFilterNearby,
                        selected: _filter == MatchFilter.nearby,
                        onTap: () => _setFilter(MatchFilter.nearby),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: AppLocalizations.of(context).matchFilterSimilarTime,
                        selected: _filter == MatchFilter.time,
                        onTap: () => _setFilter(MatchFilter.time),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: pending.isEmpty && waiting.isEmpty && decided.isEmpty
                    ? _EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: AppLocalizations.of(context).matchesFilteredEmptyTitle,
                        body: AppLocalizations.of(context).matchesFilteredEmptyBody,
                      )
                    : ListView(
                        // Always scrollable so pull-to-refresh works on a short list.
                        physics: const AlwaysScrollableScrollPhysics(),
                        // Bottom room so the last card's buttons can scroll clear of the
                        // floating "Report item" button.
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        children: [
                          const MatchLegendCard(),
                          if (pending.isNotEmpty) ...[
                            Text(AppLocalizations.of(context).matchesSectionNeedsInput,
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            for (final match in pending) ...[
                              MatchCard(key: ValueKey(match.matchId), match: match),
                              const SizedBox(height: 12),
                            ],
                            if (pendingPage.hasMore)
                              ShowMoreButton(
                                loading: pendingAsync.isLoading,
                                onPressed: () =>
                                    setState(() => _pendingLimit += kListPageSize),
                              ),
                          ],
                          if (waiting.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(AppLocalizations.of(context).matchesSectionWaiting,
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            for (final match in waiting) ...[
                              MatchCard(key: ValueKey(match.matchId), match: match),
                              const SizedBox(height: 12),
                            ],
                            if (waitingPage.hasMore)
                              ShowMoreButton(
                                loading: waitingAsync.isLoading,
                                onPressed: () =>
                                    setState(() => _waitingLimit += kListPageSize),
                              ),
                          ],
                          if (decided.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(AppLocalizations.of(context).matchesSectionDecided,
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            for (final match in decided) ...[
                              MatchCard(key: ValueKey(match.matchId), match: match),
                              const SizedBox(height: 12),
                            ],
                            if (decidedPage.hasMore)
                              ShowMoreButton(
                                loading: decidedAsync.isLoading,
                                onPressed: () =>
                                    setState(() => _decidedLimit += kListPageSize),
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          );
        }),
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
