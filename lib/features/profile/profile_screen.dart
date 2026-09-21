import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/auth_providers.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../items/data/items_providers.dart';
import 'data/profile_providers.dart';

/// Account screen. The header reflects the real signed-in user and their
/// actual rating (from the `ratings` table via `profiles.rating`, kept in
/// sync by a trigger — see Phase 8 in the README). The admin entry only
/// renders for profiles.is_admin — RLS backs that up server-side too.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.warning_amber_rounded,
      title: 'Delete your account?',
      message: 'This signs you out for good and removes your name, photo, and phone number. '
          'Every item you posted is taken down too. This is not something you can undo '
          'yourself afterward — if you change your mind later, you would need to contact '
          'support.',
      confirmLabel: 'Delete account',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(profileRepositoryProvider).requestAccountDeletion();
      ref.invalidate(itemsFeedProvider);
      // No manual navigation needed — the router's redirect callback
      // sends signed-out users to /login automatically, same as the
      // plain "Sign out" button below.
      await supabase.auth.signOut();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete your account. Try again.")),
      );
    }
  }

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
          const _AppearanceTile(),
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
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
            title: Text('Delete account', style: TextStyle(color: theme.colorScheme.error)),
            onTap: () => _deleteAccount(context, ref),
          ),
        ],
      ),
    );
  }
}

/// Manual light/dark/system picker (see item 14) — a ListTile that opens a
/// small dialog rather than cycling through a single toggle icon, so all
/// three states (including "match device") stay a single tap away and
/// visible at once rather than needing to be cycled through blind.
class _AppearanceTile extends ConsumerWidget {
  const _AppearanceTile();

  String _label(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System default';
    }
  }

  IconData _icon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, ThemeMode current) async {
    final theme = Theme.of(context);
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Appearance'),
        children: [
          for (final mode in ThemeMode.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, mode),
              child: Row(
                children: [
                  Icon(
                    _icon(mode),
                    size: 20,
                    color: mode == current ? theme.colorScheme.primary : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _label(mode),
                      style: mode == current
                          ? TextStyle(
                              color: theme.colorScheme.primary, fontWeight: FontWeight.w600)
                          : null,
                    ),
                  ),
                  if (mode == current) Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) {
      await ref.read(themeModeProvider.notifier).setThemeMode(selected);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return ListTile(
      leading: Icon(_icon(mode)),
      title: const Text('Appearance'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_label(mode), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => _pick(context, ref, mode),
    );
  }
}
