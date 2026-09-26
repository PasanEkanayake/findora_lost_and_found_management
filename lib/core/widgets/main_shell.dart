import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'tab_back_guard.dart';
import '../../features/chat/data/messages_providers.dart';
import '../../features/contact/data/contact_providers.dart';
import '../../features/home/item_feed_screen.dart';
import '../../features/matches/data/embedding_backfill_provider.dart';
import '../../features/matches/data/matches_providers.dart';

/// Bottom navigation shell for the four persistent tabs (Browse, Matches,
/// Chats, Profile). The floating action button is deliberately outside the
/// tab stack — posting an item is a one-off action, not a destination that
/// should keep its own back-stack or a permanently-selected tab.
///
/// It only shows on Browse and Matches (branches 0 and 1) — reporting an
/// item is relevant while browsing or checking matches, not while chatting
/// or looking at your own profile, and a floating button sitting over
/// every screen regardless of context reads as clutter rather than a
/// clear call to action. It also hides specifically when Browse is
/// showing its map view (see [feedShowsMapProvider]) — a full-screen map
/// has no good place to float it, and "report an item" isn't a
/// map-relevant action to begin with.
///
/// Browse (branch 0) is the app's effective "home". The Android back
/// button on a tab's root screen is handled by [TabBackGuard], which each
/// tab's route is wrapped in (see app_router.dart) — that's where the
/// "Leave Findora?" confirmation actually comes from. See TabBackGuard's
/// doc for why it can't just live here: go_router sends back presses to
/// the active tab's own nested navigator, not to this widget's route.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _branchesWithReportFab = {0, 1};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Starts the one-off catch-up that gives this user's older photos an AI
    // embedding, whichever tab they land on (see the provider's doc for why
    // it can't wait for the Matches tab). The value itself isn't used.
    ref.watch(embeddingBackfillProvider);

    // Map view (Browse tab) shows its own full-screen layout with no room
    // for a floating action button sitting over it, and "report an item"
    // isn't really a map-context action anyway — so the FAB hides
    // specifically for that case, on top of the normal branch check.
    final isBrowsingMap = navigationShell.currentIndex == 0 && ref.watch(feedShowsMapProvider);
    final showFab = _branchesWithReportFab.contains(navigationShell.currentIndex) && !isBrowsingMap;
    final isOnHomeTab = navigationShell.currentIndex == 0;

    return PopScope(
      // Fallback only: normally each tab's own TabBackGuard (inside the
      // tab's nested navigator) receives the back press first. This one
      // covers the case where the press is delivered to this shell's own
      // route instead, and runs the identical logic so both paths behave
      // the same. Pushed screens (item detail, chat, ...) sit above this
      // route, so they pop normally and never reach either guard.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        handleTabBack(context, ref, isHomeTab: isOnHomeTab);
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
            // These tabs stay mounted offscreen (see above), so their
            // data is otherwise only fetched once — a match created by
            // *someone else's* post, or a new confirmed chat, wouldn't
            // appear until a manual pull-to-refresh. Refetch whenever the
            // tab is opened instead.
            if (index == 1) {
              ref.invalidate(matchesProvider);
            } else if (index == 2) {
              ref.invalidate(conversationsProvider);
              ref.invalidate(contactThreadsProvider);
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

