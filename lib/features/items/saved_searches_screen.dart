import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/items_providers.dart';
import 'data/saved_search_repository.dart';

/// Saved searches: each one alerts the person when a NEW post matching it is
/// made in the same country. Searches are saved from Browse (the filter button
/// → "Save this search"); here they can be switched off or deleted.
class SavedSearchesScreen extends ConsumerWidget {
  const SavedSearchesScreen({super.key});

  Future<void> _toggle(BuildContext context, WidgetRef ref, SavedSearch search, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(savedSearchRepositoryProvider).setActive(search.id, on);
      ref.invalidate(savedSearchesProvider);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't change that. Try again.")),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, SavedSearch search) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(savedSearchRepositoryProvider).delete(search.id);
      ref.invalidate(savedSearchesProvider);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't delete that. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchesAsync = ref.watch(savedSearchesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved searches')),
      body: searchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text("Couldn't load your saved searches.")),
        data: (searches) {
          if (searches.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No saved searches yet.\n\nIn Browse, type a search or pick a category, '
                  'tap the filter button, and choose "Save this search" — you will get an '
                  'alert when a new matching post appears.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: searches.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Text(
                    'You are alerted about new matching posts in the same country — at most '
                    'one alert per search every 30 minutes. You can save up to 10 searches.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                );
              }
              final search = searches[index - 1];
              return ListTile(
                title: Text(search.label),
                subtitle: Text(search.active ? 'Alerts on' : 'Alerts off'),
                leading: Icon(
                  search.active ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                  color: search.active ? theme.colorScheme.primary : theme.colorScheme.outline,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: search.active,
                      onChanged: (value) => _toggle(context, ref, search, value),
                    ),
                    IconButton(
                      tooltip: 'Delete this saved search',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, ref, search),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
