import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/push_notifications.dart';
import 'data/profile_providers.dart';

/// Real settings, not decorative ones: reads the OS-level notification
/// permission via FirebaseMessaging, and the toggle actually registers or
/// clears this device's push token on the user's profile — the same
/// token `record_matches_for_image`'s future server-side sender (see
/// README, Phase 7) would target.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  AuthorizationStatus? _osPermission;
  bool _isLoadingPermission = true;
  bool _isTogglingPush = false;

  @override
  void initState() {
    super.initState();
    _loadPermissionStatus();
  }

  Future<void> _loadPermissionStatus() async {
    setState(() => _isLoadingPermission = true);
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (mounted) setState(() => _osPermission = settings.authorizationStatus);
    } catch (_) {
      // Firebase not configured yet (see README, "Firebase setup") — the
      // toggle below still works for the app-side opt-in/out, it just
      // can't report an OS permission status.
      if (mounted) setState(() => _osPermission = null);
    } finally {
      if (mounted) setState(() => _isLoadingPermission = false);
    }
  }

  Future<void> _requestPermission() async {
    await FirebaseMessaging.instance.requestPermission();
    await _loadPermissionStatus();
    if (_osPermission == AuthorizationStatus.authorized) {
      await registerPushTokenForCurrentUser();
      ref.invalidate(myProfileProvider);
    }
  }

  Future<void> _togglePush(bool enabled) async {
    setState(() => _isTogglingPush = true);
    try {
      if (enabled) {
        await registerPushTokenForCurrentUser();
      } else {
        await clearPushToken();
      }
      ref.invalidate(myProfileProvider);
    } finally {
      if (mounted) setState(() => _isTogglingPush = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(myProfileProvider);
    final osDenied = _osPermission == AuthorizationStatus.denied;

    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isLoadingPermission)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (osDenied)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications are blocked at the system level',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.onErrorContainer),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Enable them in your phone\'s Settings > Apps > Findora > '
                      'Notifications to receive match and message alerts.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onErrorContainer),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _requestPermission,
                      child: const Text('Try requesting again'),
                    ),
                  ],
                ),
              ),
            )
          else if (_osPermission != AuthorizationStatus.authorized)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Turn on notifications', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      "Get notified when someone confirms a match or sends you a message.",
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _requestPermission,
                      child: const Text('Enable notifications'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          profileAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (profile) => SwitchListTile(
              title: const Text('Push notifications'),
              subtitle: Text(
                profile.fcmToken != null
                    ? 'This device will receive push alerts'
                    : "This device won't receive push alerts",
              ),
              value: profile.fcmToken != null,
              onChanged: (_osPermission == AuthorizationStatus.authorized && !_isTogglingPush)
                  ? _togglePush
                  : null,
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Findora currently sends alerts for new AI-suggested matches and '
              'new chat messages. You can turn these off entirely with the '
              'switch above at any time.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
