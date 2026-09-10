import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../constants/app_constants.dart';
import '../supabase/supabase_client.dart';

final _localNotifications = FlutterLocalNotificationsPlugin();

/// Sets up FCM (permission request, foreground message handling via a
/// local notification) and registers this device's token. Safe to call
/// even if Firebase isn't configured yet — main.dart wraps this in a
/// try/catch, so a missing google-services.json degrades to "no push
/// notifications" rather than a crash, the same pattern used for the
/// TFLite model and the Google Maps API key elsewhere in this app.
///
/// What this does NOT do: actually send a notification when a match or
/// message happens. That's a server-side piece — a Supabase Edge Function
/// (using the FCM HTTP v1 API) triggered by a Database Webhook on inserts
/// into `matches`/`messages` — which needs a Firebase service account key
/// this sandbox has no way to hold securely. See README.md.
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
  await supabase.from(AppConstants.profilesTable).update({'fcm_token': token}).eq('id', userId);
}
