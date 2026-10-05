import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'data/notification_model.dart';
import 'data/notifications_providers.dart';

/// The Notifications tab: every new match, match confirmation, claim
/// filed/decided, return, and rating, newest first — see
/// supabase/14_notifications.sql's header for exactly what is and isn't
/// covered (chat messages deliberately aren't, to avoid burying these
/// under much more frequent message activity).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, NotificationModel notification) async {
    if (notification.isUnread) {
      // Fire-and-forget: the list already shows it as read optimistically
      // via the invalidate below, so there's nothing to await before
      // navigating — and if this particular write fails, the worst case
      // is the badge is one count off until the next refresh, not
      // something worth blocking navigation over.
      unawaited(
        ref.read(notificationsRepositoryProvider).markRead(notification.id).then(
              (_) => ref.invalidate(notificationsProvider),
            ),
      );
    }
    context.push(notification.destinationRoute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notificationsAsync = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(unreadNotificationsCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: () async {
                await ref.read(notificationsRepositoryProvider).markAllRead();
                ref.invalidate(notificationsProvider);
              },
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Couldn't load notifications.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(notificationsProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(notificationsProvider);
                await ref.read(notificationsProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 96, horizontal: 32),
                    child: Column(
                      children: [
                        Icon(Icons.notifications_none_rounded,
                            size: 48, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text('Nothing yet', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          "You'll see new matches, claims, returns and ratings here.",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationsProvider);
              await ref.read(notificationsProvider.future);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return _NotificationTile(
                  key: ValueKey(notification.id),
                  notification: notification,
                  onTap: () => _open(context, ref, notification),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({super.key, required this.notification, required this.onTap});

  final NotificationModel notification;
  final VoidCallback onTap;

  (IconData, Color Function(ColorScheme)) get _iconAndColor => switch (notification.type) {
        'new_match' => (Icons.auto_awesome, (cs) => cs.primary),
        'match_confirmed' => (Icons.chat_bubble_outline, (cs) => cs.primary),
        'claim_filed' => (Icons.assignment_outlined, (cs) => cs.primary),
        'claim_approved' => (Icons.check_circle_outline, (cs) => cs.tertiary),
        'claim_rejected' => (Icons.cancel_outlined, (cs) => cs.error),
        'item_returned' => (Icons.task_alt, (cs) => cs.tertiary),
        'new_rating' => (Icons.star_outline_rounded, (cs) => cs.secondary),
        _ => (Icons.notifications_outlined, (cs) => cs.onSurfaceVariant),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, colorOf) = _iconAndColor;
    final color = colorOf(theme.colorScheme);
    final isUnread = notification.isUnread;

    return Material(
      color: isUnread ? theme.colorScheme.primaryContainer.withValues(alpha: 0.18) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (notification.body != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        notification.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _relativeTime(notification.createdAt),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 8),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.yMMMd().format(time);
  }
}
