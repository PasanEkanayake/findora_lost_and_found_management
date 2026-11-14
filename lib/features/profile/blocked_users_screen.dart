import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../chat/data/safety_providers.dart';
import '../chat/data/safety_repository.dart';

/// People the signed-in user has blocked, with a way to undo it. Blocking is
/// done from the ⋮ menu inside a chat (see ChatSafetyMenu).
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  Future<void> _unblock(BuildContext context, WidgetRef ref, BlockedUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(safetyRepositoryProvider).unblock(user.userId);
      ref.invalidate(blockedUsersProvider);
      ref.invalidate(blockedUserIdsProvider);
      messenger.showSnackBar(SnackBar(content: Text('Unblocked ${user.name}.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't unblock. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(blockedUsersProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked people')),
      body: blockedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text("Couldn't load your blocked list.")),
        data: (users) {
          if (users.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  "You haven't blocked anyone.\n\nYou can block someone from the ⋮ menu "
                  'inside a chat.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_off_outlined)),
                title: Text(user.name),
                subtitle: Text('Blocked ${DateFormat.yMMMd().format(user.blockedAt.toLocal())}'),
                trailing: TextButton(
                  onPressed: () => _unblock(context, ref, user),
                  child: const Text('Unblock'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
