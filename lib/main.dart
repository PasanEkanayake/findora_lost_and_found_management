import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/auth_error_notifier.dart';
import 'core/connectivity/connectivity_provider.dart';
import 'core/l10n/locale_controller.dart';
import 'core/notifications/push_notifications.dart';
import 'core/providers/auth_providers.dart';
import 'core/router/app_router.dart';
import 'core/supabase/secure_session_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'core/widgets/offline_banner.dart';
import 'features/items/data/items_providers.dart';
import 'features/matches/data/matches_providers.dart';
import 'features/notifications/data/notifications_providers.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loads SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY from a local .env file
  // that is never committed. See README.md, step 3.
  await dotenv.load(fileName: '.env');

  // Date/number formatting data for every language (English, Sinhala, Tamil).
  await initializeDateFormatting();

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    // `publishableKey` is the current parameter name (Supabase is retiring
    // the old `anonKey` terminology in favor of publishable/secret keys).
    publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
    // The session (including the long-lived refresh token) lives in the
    // Android Keystore, not in readable app data.
    authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
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
    // Shows why a browser sign-in (Google) failed — e.g. an address still in its
    // waiting period after an account deletion. See auth_error_notifier.dart.
    ref.watch(authErrorNoticeProvider);
    final chosenLocale = ref.watch(localeProvider);

    // `intl` (dates, numbers) doesn't follow MaterialApp.locale, so tell it
    // which language the app is actually showing.
    applyIntlLocale(
      resolveLocale(chosenLocale, WidgetsBinding.instance.platformDispatcher.locales),
    );

    // A notification that cold-started the app (see
    // push_notifications.dart's getInitialMessage handling) left a route
    // waiting for exactly this moment — the router above now exists, so
    // it's finally safe to act on it. Scheduled for after this frame
    // rather than during build, since navigating is a side effect and
    // the splash/redirect flow needs to run its own first frame normally.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingRoute = consumePendingNotificationRoute();
      if (pendingRoute != null) router.push(pendingRoute);
    });

    // Re-registers the push token on every sign-in, not just at cold
    // start — a token fetched before login has nobody to be saved against.
    ref.listen(currentUserProvider, (previous, next) {
      if (next != null) registerPushTokenForCurrentUser();
    });

    // Coming back online: lists that failed to load while offline reload
    // themselves instead of waiting for a manual pull-to-refresh.
    ref.listen<bool>(connectivityProvider, (previous, next) {
      if (previous == false && next) {
        ref.invalidate(itemsFeedProvider);
        ref.invalidate(matchesProvider);
        ref.invalidate(notificationsProvider);
      }
    });

    return MaterialApp.router(
      title: 'Findora',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      // null = follow the phone's language; otherwise the person's choice in
      // Profile -> Language. Falls back to English for anything untranslated.
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      locale: chosenLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
      // The "You're offline" banner (see OfflineBannerHost).
      builder: (context, child) => OfflineBannerHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
