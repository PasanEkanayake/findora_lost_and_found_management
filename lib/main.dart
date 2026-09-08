import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

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

  runApp(const ProviderScope(child: LostAndFoundApp()));
}

class LostAndFoundApp extends ConsumerWidget {
  const LostAndFoundApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Findora',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
