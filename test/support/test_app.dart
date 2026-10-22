import 'package:findora/core/connectivity/connectivity_provider.dart';
import 'package:findora/features/items/data/items_repository.dart';
import 'package:findora/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared helpers for the widget and integration tests.
///
/// The app cannot be started as a whole in a test: `Supabase.instance.client`
/// (the global `supabase` in lib/core/supabase/supabase_client.dart) only
/// exists after `Supabase.initialize()`, which needs a real project. So these
/// tests put a REAL screen in a ProviderScope and replace the repositories it
/// reads with in-memory fakes that follow the same rules as the database
/// (see fake_matches_repository.dart). Nothing here touches the network.

/// A theme with the same BUTTON rules as the real app (lib/core/theme/app_theme.dart
/// makes every FilledButton/OutlinedButton full-width with `Size.fromHeight(52)`).
/// Tests use it by default so a layout that only breaks under those rules — a
/// button placed directly in a Row — fails here instead of silently drawing a
/// blank screen in a release build. (The real theme isn't used because it loads
/// Google Fonts over the network.)
ThemeData testTheme() => ThemeData(
      useMaterial3: true,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
    );

/// Lets the UI settle without `pumpAndSettle`, which never returns while an
/// endless animation (shimmer, progress bars) is on screen.
Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps [home] inside a ProviderScope + MaterialApp and lets it settle.
///
/// [locale] is the language the screen is shown in (default English).
///
/// [resizeView] gives the test a tall phone-like surface so long lists build
/// more rows; pass false in `integration_test`, where the real device screen
/// is used.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
  bool resizeView = true,
  TransitionBuilder? builder,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  SharedPreferences.setMockInitialValues({});
  if (resizeView) {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 retries a failed provider with a timer; a test that checks
      // an error state must not be left with a pending timer.
      retry: (_, __) => null,
      overrides: overrides,
      child: MaterialApp(
        builder: builder,
        theme: theme ?? testTheme(),
        // The app's real localizations (English unless a test asks otherwise),
        // so screens that read AppLocalizations work.
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: home,
      ),
    ),
  );
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// The vertical list of a screen (not a horizontal chip row), to scroll.
Finder verticalList() {
  final list = find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.vertical);
  return find.descendant(of: list, matching: find.byType(Scrollable)).first;
}

/// An ItemsRepository that finds nothing to scan. MatchesScreen quietly looks
/// for photos missing an AI embedding when it opens, which would otherwise
/// reach for the (uninitialised) Supabase client.
class FakeItemsRepository implements ItemsRepository {
  @override
  Future<List<({String id, String url})>> fetchMyImagesMissingEmbeddings() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The connectivity monitor without its timers or sockets: the test flips it.
class FakeConnectivity extends ConnectivityController {
  @override
  bool build() => true;

  void setOnline(bool online) => state = online;
}
