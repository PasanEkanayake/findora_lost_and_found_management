import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'safety_repository.dart';

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  return const SafetyRepository();
});

/// Everyone the signed-in user has blocked. Falls back to "nobody" if it
/// can't be loaded (offline, or supabase/20_chat_safety.sql not applied yet),
/// so chat lists keep working — the server still enforces blocks either way.
final blockedUserIdsProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  try {
    return await ref.watch(safetyRepositoryProvider).fetchBlockedIds();
  } catch (_) {
    return <String>{};
  }
});

final blockedUsersProvider = FutureProvider.autoDispose<List<BlockedUser>>((ref) {
  return ref.watch(safetyRepositoryProvider).fetchBlockedUsers();
});
