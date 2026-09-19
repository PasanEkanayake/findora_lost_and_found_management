import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/notifications/push_notifications.dart';
import 'core/providers/auth_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loads SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY from a local .env file
  // that is never committed. See README.md, step 3.
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    // `publishableKey` is the current parameter name (Supabase is retiring
    // the old `anonKey` terminology in favor of publishable/secret keys).
    publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
  );

  // Firebase.initializeApp() with no explicit options works on Android as
  // long as google-services.json is in place natively — no generated
  // firebase_options.dart needed for an Android-only app. Wrapped in a
  // try/catch so skipping Firebase setup degrades to "no push
  // notifications" instead of the app failing to start.
  try {
    await Firebase.initializeApp();
    await initializePushNotifications();
  } catch (e) {
    debugPrint('Push notifications unavailable (Firebase not configured yet): $e');
  }

  runApp(const ProviderScope(child: FindoraApp()));
}

class FindoraApp extends ConsumerWidget {
  const FindoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Re-registers the push token on every sign-in, not just at cold
    // start — a token fetched before login has nobody to be saved against.
    ref.listen(currentUserProvider, (previous, next) {
      if (next != null) registerPushTokenForCurrentUser();
    });

    return MaterialApp.router(
      title: 'Findora',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
