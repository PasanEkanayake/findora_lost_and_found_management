import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../matches/data/matches_providers.dart';
import '../data/item_model.dart';
import '../data/items_providers.dart';

/// How close to expiry a post gets nudged ("Keep it up").
const int kExpiryWarningDays = 14;

/// Renews [item] (a fresh 60 days; brings an expired post back) and refreshes
/// everything that shows it. Shared by the post page banner and My posts.
/// Shows a snackbar with the result; returns whether it worked.
Future<bool> renewPost(BuildContext context, WidgetRef ref, ItemModel item) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  try {
    await ref.read(itemsRepositoryProvider).renewItem(item.id);
    ref.invalidate(itemDetailProvider(item.id));
    ref.invalidate(myItemsProvider);
    ref.invalidate(itemsFeedProvider);
    ref.invalidate(nearbyItemsProvider);
    ref.invalidate(matchesProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(item.isExpired ? l10n.expiryRenewedBack : l10n.expiryKeptUp),
      ),
    );
    return true;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(friendlyDatabaseError(e, fallback: l10n.expiryRenewFailed)),
      ),
    );
    return false;
  }
}

/// On the post page, for its OWNER only: says when the post expires once it is
/// within two weeks, or that it already has — with the button to keep it up.
/// Takes no space for everyone else, and for posts with plenty of time left.
class ItemExpiryBanner extends ConsumerWidget {
  const ItemExpiryBanner({super.key, required this.item});

  final ItemModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    if (myId == null || item.userId != myId) return const SizedBox.shrink();

    final expired = item.isExpired;
    if (!expired && !item.isExpiringWithin(kExpiryWarningDays)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final days = item.daysUntilExpiry() ?? 0;
    // One plural message covers "within a day" (0 or 1) and "in N days", in
    // each language's own plural rules.
    final message = expired ? l10n.expiryExpired : l10n.expiryExpiringDays(days);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: expired
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.6)
            : theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(expired ? Icons.timer_off_outlined : Icons.hourglass_bottom_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => renewPost(context, ref, item),
            // Not full-width (the theme default) — this sits in a Row.
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            child: Text(expired ? l10n.expiryRenew : l10n.expiryKeepItUp),
          ),
        ],
      ),
    );
  }
}
