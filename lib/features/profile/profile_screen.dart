import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/auth_providers.dart';
import '../../core/supabase/supabase_client.dart';
import 'data/profile_providers.dart';

/// Account screen. The header reflects the real signed-in user and their
/// actual rating (from the `ratings` table via `profiles.rating`, kept in
/// sync by a trigger — see Phase 8 in the README). The admin entry only
/// renders for profiles.is_admin — RLS backs that up server-side too.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final profileAsync = ref.watch(myProfileProvider);

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
                  backgroundImage: profileAsync.maybeWhen(
                    data: (profile) => profile.avatarUrl != null
                        ? CachedNetworkImageProvider(profile.avatarUrl!)
                        : null,
                    orElse: () => null,
                  ),
                  child: profileAsync.maybeWhen(
                    data: (profile) => profile.avatarUrl == null
                        ? Icon(Icons.person_outline,
                            size: 32, color: theme.colorScheme.onPrimaryContainer)
                        : null,
                    orElse: () => Icon(Icons.person_outline,
                        size: 32, color: theme.colorScheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: profileAsync.when(
                    loading: () => Text(
                      'Loading…',
                      style: theme.textTheme.titleLarge,
                    ),
                    // Falls back to the auth user's email directly, rather
                    // than showing nothing, if the profiles row somehow
                    // can't be fetched.
                    error: (_, __) => Text(
                      user?.email ?? 'Your name',
                      style: theme.textTheme.titleLarge,
                    ),
                    data: (profile) {
                      // full_name is what the signup form actually
                      // collects (see signup_screen.dart); username is
                      // just an email-derived fallback set by the
                      // handle_new_user trigger, never chosen by the user.
                      final hasFullName = profile.fullName?.trim().isNotEmpty ?? false;
                      final displayName = hasFullName
                          ? profile.fullName!
                          : (profile.username ?? user?.email ?? 'Your name');

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(displayName, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.star_rounded,
                                  size: 16, color: theme.colorScheme.secondary),
                              const SizedBox(width: 4),
                              Text(
                                profile.ratingCount == 0
                                    ? 'No ratings yet'
                                    : '${profile.rating.toStringAsFixed(1)} '
                                        '(${profile.ratingCount} review${profile.ratingCount == 1 ? '' : 's'})',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit profile',
                  onPressed: () => context.push('/profile/edit'),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('My reported items'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/my-items'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/notifications'),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Privacy & safety'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/privacy-safety'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/help'),
          ),
          profileAsync.maybeWhen(
            data: (profile) => profile.isAdmin
                ? ListTile(
                    leading: Icon(Icons.admin_panel_settings_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('Flagged reports'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/admin/reports'),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
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
