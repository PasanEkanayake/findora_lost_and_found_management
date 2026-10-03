import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/item_feed_screen.dart';
import 'confirm_dialog.dart';

/// Asks "Leave Findora?" and, only if confirmed, closes the app.
Future<void> confirmAndExitApp(BuildContext context) async {
  final confirmed = await showConfirmDialog(
    context,
    icon: Icons.waving_hand_outlined,
    title: 'Leave Findora?',
    message: "You'll stop seeing new match alerts while the app is closed.",
    confirmLabel: 'Exit app',
    cancelLabel: 'Stay',
  );
  if (confirmed) SystemNavigator.pop();
}

/// What the Android back button does when a bottom-nav tab is showing at
/// its root (nothing else pushed on top of it):
///
/// - Any tab other than Browse: go back to Browse — the usual bottom-nav
///   convention, and it means exiting always takes a deliberate second
///   press from the "home" screen.
/// - Browse, with the map view open: back to the list view first.
/// - Browse, list view (the actual home page): confirm before exiting.
void handleTabBack(BuildContext context, WidgetRef ref, {required bool isHomeTab}) {
  if (!isHomeTab) {
    context.go('/feed');
    return;
  }
  if (ref.read(feedShowsMapProvider)) {
    ref.read(feedShowsMapProvider.notifier).setShowsMap(false);
    return;
  }
  confirmAndExitApp(context);
}

/// Wraps a tab's root screen (see the five `StatefulShellBranch` routes in
/// core/router/app_router.dart) so the back button is handled by
/// [handleTabBack] instead of silently closing the app.
///
/// **Why this lives inside each tab's route and not once in `MainShell`.**
/// An earlier version put a single `PopScope` in `MainShell` and the exit
/// dialog never appeared. `MainShell` is built by the *root* navigator,
/// but go_router routes an Android back press to the navigator of the
/// currently active tab — a separate, nested `Navigator` sitting inside
/// `MainShell`. That nested navigator has exactly one route (the tab's
/// root screen) and no `PopScope` of its own, so it reported "nothing to
/// pop", the press fell through to the operating system, and the app
/// closed without the root-level `PopScope` ever being consulted. A
/// `PopScope` has to be inside the route of the navigator that actually
/// receives the press, which is what this widget is for.
///
/// `canPop` is always false: every back press on a tab root is handled
/// here, never left to fall through and exit.
class TabBackGuard extends ConsumerWidget {
  const TabBackGuard({super.key, required this.isHomeTab, required this.child});

  /// True only for the Browse tab, the app's home page.
  final bool isHomeTab;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        handleTabBack(context, ref, isHomeTab: isHomeTab);
      },
      child: child,
    );
  }
}
