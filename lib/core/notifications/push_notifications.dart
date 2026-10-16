import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../router/app_router.dart' show rootRouter;
import '../supabase/supabase_client.dart';
import '../../features/notifications/data/notifications_repository.dart';

final _localNotifications = FlutterLocalNotificationsPlugin();

/// Sets up FCM (permission request, foreground message handling via a
/// local notification) and registers this device's token. Safe to call
/// even if Firebase isn't configured yet — main.dart wraps this in a
/// try/catch, so a missing google-services.json degrades to "no push
/// notifications" rather than a crash, the same pattern used for the
/// TFLite model and the Google Maps API key elsewhere in this app.
///
/// The actual *sending* of a push happens server-side — the
/// `send-push-notification` Edge Function
/// (supabase/functions/send-push-notification/), triggered by a Database
/// Webhook whenever a row lands in `notifications`
/// (supabase/14_notifications.sql). Setting that up needs a Firebase
/// service account key from your own project, a real secret this sandbox
/// has no way to hold — see README.md, "Sending real push notifications".
Future<void> initializePushNotifications() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();

  await _localNotifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  FirebaseMessaging.onMessage.listen((message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'findora_default',
          'Findora notifications',
          importance: Importance.high,
        ),
      ),
    );
  });

  messaging.onTokenRefresh.listen(_saveToken);
  await registerPushTokenForCurrentUser();

  // Tapped while the app was merely backgrounded (not killed) — the
  // router already exists by the time this can fire, so it's safe to
  // navigate immediately.
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final route = _handleTappedMessage(message);
    if (route != null) rootRouter?.push(route);
  });

  // Tapped while the app was fully closed, which is *this* call —
  // cold-starting the app — so there is no router yet (this runs inside
  // main(), before runApp()). Stash the route rather than navigating, for
  // FindoraApp's first frame to pick up once the router exists — see
  // consumePendingNotificationRoute's doc.
  final initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null) {
    _pendingRoute = _handleTappedMessage(initialMessage);
  }
}

/// Reads where a tapped notification should go (the same route
/// `NotificationModel.destinationRoute` would compute — the Edge Function
/// sends it pre-computed in the `data` payload, see that function's
/// `destinationRoute()`), and marks the notification read. Marking read
/// is fire-and-forget: if it fails, the worst case is the Alerts badge is
/// briefly one count off, not worth blocking navigation over.
String? _handleTappedMessage(RemoteMessage message) {
  final notificationId = message.data['notification_id'] as String?;
  if (notificationId != null) {
    const NotificationsRepository().markRead(notificationId).catchError((e) {
      debugPrint('Could not mark notification read from a push tap: $e');
    });
  }
  return message.data['route'] as String?;
}

String? _pendingRoute;

/// Consumes (returns once, then clears) the route stashed by a
/// cold-start notification tap — see initializePushNotifications's
/// getInitialMessage handling above for why this can't just navigate
/// directly. FindoraApp calls this on its first frame, once the router
/// it needs is guaranteed to exist.
String? consumePendingNotificationRoute() {
  final route = _pendingRoute;
  _pendingRoute = null;
  return route;
}

/// Saves this device's current FCM token to the signed-in user's profile.
/// Safe to call repeatedly — it's just an update of one column — and a
/// no-op if nobody's signed in yet. Called once at startup (in case a
/// session already exists) and again on every sign-in (see main.dart's
/// `ref.listen(currentUserProvider, ...)`), since a token fetched before
/// login has nowhere to be saved yet.
Future<void> registerPushTokenForCurrentUser() async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;

  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await _saveToken(token);
  } catch (e) {
    debugPrint('Could not register push token: $e');
  }
}

Future<void> _saveToken(String token) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;
  // One row per device (supabase/21_device_tokens.sql). The function moves the
  // token over if another account was last signed in on this phone.
  await supabase.rpc('register_device_token', params: {
    'p_token': token,
    'p_platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
  });
}

/// Removes THIS device's push token — used by the "push notifications"
/// toggle in NotificationSettingsScreen, and on sign-out so a phone that is
/// no longer signed in stops receiving that person's notifications. Doesn't
/// revoke the OS-level permission (apps can't do that for the user), it just
/// stops this profile from being a valid target for a future server-side
/// push send.
///
/// Must run while still signed in (the write is the signed-in user's own),
/// i.e. BEFORE `auth.signOut()`. Never throws: a failure here must not stop
/// someone signing out.
Future<void> clearPushToken() async {
  if (supabase.auth.currentUser == null) return;
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    // Removes only THIS device — the person's other phones keep working.
    await supabase.rpc('unregister_device_token', params: {'p_token': token});
  } catch (e) {
    debugPrint('Could not clear push token: $e');
  }
}

/// Whether THIS phone is currently registered to receive the signed-in
/// person's push notifications (drives the switch in notification settings).
/// Per device, not per account: the same person may be signed in elsewhere.
final thisDeviceRegisteredProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return false;
    final rows = await supabase
        .from('device_tokens')
        .select('token')
        .eq('token', token)
        .limit(1);
    return rows.isNotEmpty;
  } catch (_) {
    return false;
  }
});
