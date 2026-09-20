import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'confirm_dialog.dart';
import '../../features/home/item_feed_screen.dart';

/// Bottom navigation shell for the four persistent tabs (Browse, Matches,
/// Chats, Profile). The floating action button is deliberately outside the
/// tab stack — posting an item is a one-off action, not a destination that
/// should keep its own back-stack or a permanently-selected tab.
///
/// It only shows on Browse and Matches (branches 0 and 1) — reporting an
/// item is relevant while browsing or checking matches, not while chatting
/// or looking at your own profile, and a floating button sitting over
/// every screen regardless of context reads as clutter rather than a
/// clear call to action.
///
/// Browse (branch 0) is the app's effective "home" — go_router's
/// StatefulShellRoute keeps a separate navigation stack per tab, so a back
/// press while on Browse's root has nowhere else in the app to go. Rather
/// than let that fall through to backing out of the app instantly, a
/// PopScope here intercepts exactly that case and asks for confirmation
/// first; every other tab keeps Android's normal back behavior (which
/// go_router/Navigator resolve on their own — switching to a previous tab
/// or popping a pushed screen).
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _branchesWithReportFab = {0, 1};

  Future<void> _confirmExit(BuildContext context) async {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showFab = _branchesWithReportFab.contains(navigationShell.currentIndex);
    final isOnHomeTab = navigationShell.currentIndex == 0;

    return PopScope(
      // Only the Browse tab's root has no further "back" to fall through
      // to (see class doc) — everywhere else, let the platform/router
      // handle it exactly as it already does.
      canPop: !isOnHomeTab,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !isOnHomeTab) return;
        _confirmExit(context);
      },
      child: Scaffold(
        body: navigationShell,
        floatingActionButton: showFab
            ? FloatingActionButton.extended(
                onPressed: () => context.push('/post-item'),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Report item'),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            // Tapping Browse always lands on the list/home view, even if
            // the map view was left open — either switching in from
            // another tab, or tapping Browse again while already there,
            // both read as "take me home" and should behave the same way.
            // ItemFeedScreen stays mounted-but-offscreen while another tab
            // is active (see feedShowsMapProvider's doc), so this can't be
            // done by ItemFeedScreen resetting its own state on init —
            // nothing re-inits it on a tab switch.
            if (index == 0) {
              ref.read(feedShowsMapProvider.notifier).setShowsMap(false);
            }
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'Browse',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'Matches',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

