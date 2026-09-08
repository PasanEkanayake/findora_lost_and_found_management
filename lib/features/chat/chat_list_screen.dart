import 'package:flutter/material.dart';

/// Lists conversations tied to items (see `messages` table). Phase 6 adds
/// the real Supabase Realtime subscription; for now this is an empty state.
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: Center(
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
                child: Icon(
                  Icons.chat_bubble_outline,
                  size: 40,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text('No conversations yet', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'When you confirm a match, a chat opens automatically so you '
                'can arrange the handoff without sharing contact details '
                'up front.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
