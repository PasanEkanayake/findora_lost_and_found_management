import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/auth_providers.dart';
import '../../core/supabase/supabase_client.dart';

/// Account screen. The header now reflects the real signed-in user via
/// [currentUserProvider]; the rest of the profile data (rating, avatar)
/// still waits on Phase 3's `profiles` table wiring.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final displayName =
        (user?.userMetadata?['username'] as String?) ?? user?.email ?? 'Your name';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    size: 32,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.star_rounded,
                              size: 16, color: theme.colorScheme.secondary),
                          const SizedBox(width: 4),
                          Text(
                            'No ratings yet',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('My reported items'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Privacy & safety'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(height: 32),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Sign out', style: TextStyle(color: theme.colorScheme.error)),
            onTap: () async {
              // No manual navigation needed — the router's redirect
              // callback sends signed-out users to /login automatically.
              await supabase.auth.signOut();
            },
          ),
        ],
      ),
    );
  }
}
