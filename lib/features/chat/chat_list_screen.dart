import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'chat_screen.dart';
import 'data/conversation_model.dart';
import '../../core/widgets/shimmer_list.dart';
import 'data/messages_providers.dart';
import '../contact/contact_chat_screen.dart';
import '../contact/data/contact_providers.dart';
import '../contact/data/contact_thread_model.dart';

/// Two tabs over two independent conversation systems: confirmed AI
/// matches (chat gated behind ownership-plausible verification — see
/// Phase 5/7 notes in the README) and direct "Contact poster" threads
/// (see supabase/06_contact_messaging.sql), which anyone can start on any
/// open item. Kept as tabs on one screen rather than two nav destinations
/// so "Chats" stays a single, findable place for every conversation.
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chats'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Matches'),
              Tab(text: 'Direct messages'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _MatchConversationsTab(),
            _ContactThreadsTab(),
          ],
        ),
      ),
    );
  }
}

class _MatchConversationsTab extends ConsumerWidget {
  const _MatchConversationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(conversationsProvider.future),
      child: conversationsAsync.when(
        loading: () => const ShimmerTileList(),
        error: (_, __) => const _EmptyState(
          icon: Icons.error_outline,
          title: "Couldn't load chats",
          body: 'Check your connection and pull down to try again.',
        ),
        data: (conversations) {
          if (conversations.isEmpty) {
            return const _EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No confirmed matches yet',
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
    );
  }
}

class _ContactThreadsTab extends ConsumerWidget {
  const _ContactThreadsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(contactThreadsProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(contactThreadsProvider.future),
      child: threadsAsync.when(
        loading: () => const ShimmerTileList(),
        error: (_, __) => const _EmptyState(
          icon: Icons.error_outline,
          title: "Couldn't load messages",
          body: 'Check your connection and pull down to try again.',
        ),
        data: (threads) {
          if (threads.isEmpty) {
            return const _EmptyState(
              icon: Icons.forum_outlined,
              title: 'No direct messages yet',
              body: 'Tap "Contact poster" on any item to ask a quick '
                  "question — you don't need a confirmed match first.",
            );
          }
          return ListView.separated(
            itemCount: threads.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
            itemBuilder: (context, index) => _ContactThreadTile(threads[index]),
          );
        },
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

class _ContactThreadTile extends StatelessWidget {
  const _ContactThreadTile(this.thread);

  final ContactThreadModel thread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = thread.unreadCount > 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 52,
          height: 52,
          child: thread.itemImageUrl == null
              ? Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.image_outlined, color: theme.colorScheme.onSurfaceVariant),
                )
              : CachedNetworkImage(
                  imageUrl: thread.itemImageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: theme.colorScheme.surfaceContainerHighest),
                ),
        ),
      ),
      title: Text(
        thread.otherUserName,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        thread.lastMessage ?? 'About "${thread.itemTitle}"',
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
          if (thread.lastMessageAt != null)
            Text(
              DateFormat.MMMd().format(thread.lastMessageAt!),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            CircleAvatar(
              radius: 9,
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                '${thread.unreadCount}',
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
        '/contact-chat',
        extra: ContactChatArgs(
          threadId: thread.threadId,
          itemTitle: thread.itemTitle,
          otherUserName: thread.otherUserName,
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
