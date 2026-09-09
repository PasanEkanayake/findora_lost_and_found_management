import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'chat_screen.dart';
import 'data/conversation_model.dart';
import 'data/messages_providers.dart';

/// Lists one entry per confirmed match, via `my_conversations()`. A chat
/// only exists once a match is confirmed — see Phase 5/7 notes in the
/// README on why that gate is deliberate.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(conversationsProvider.future),
        child: conversationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _EmptyState(
            icon: Icons.error_outline,
            title: "Couldn't load chats",
            body: 'Check your connection and pull down to try again.',
          ),
          data: (conversations) {
            if (conversations.isEmpty) {
              return _EmptyState(
                icon: Icons.chat_bubble_outline,
                title: 'No conversations yet',
                body: 'When you confirm a match, a chat opens automatically so '
                    'you can arrange the handoff without sharing contact '
                    'details up front.',
              );
            }
            return ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
              itemBuilder: (context, index) => _ConversationTile(conversations[index]),
            );
          },
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile(this.conversation);

  final ConversationModel conversation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = conversation.unreadCount > 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 52,
          height: 52,
          child: conversation.matchedItemImageUrl == null
              ? Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.image_outlined, color: theme.colorScheme.onSurfaceVariant),
                )
              : CachedNetworkImage(
                  imageUrl: conversation.matchedItemImageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: theme.colorScheme.surfaceContainerHighest),
                ),
        ),
      ),
      title: Text(
        conversation.matchedItemTitle,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        conversation.lastMessage ?? 'Say hello — you two found a match!',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: hasUnread ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (conversation.lastMessageAt != null)
            Text(
              DateFormat.MMMd().format(conversation.lastMessageAt!),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            CircleAvatar(
              radius: 9,
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                '${conversation.unreadCount}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: () => context.push(
        '/chat',
        extra: ChatScreenArgs(
          matchId: conversation.matchId,
          otherUserId: conversation.otherUserId,
          otherItemTitle: conversation.matchedItemTitle,
          myItemId: conversation.myItemId,
          matchedItemId: conversation.matchedItemId,
          matchedItemType: conversation.matchedItemType,
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
                      color: theme.colorScheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 40, color: theme.colorScheme.onSecondaryContainer),
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
