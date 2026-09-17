import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _branchesWithReportFab = {0, 1};

  @override
  Widget build(BuildContext context) {
    final showFab = _branchesWithReportFab.contains(navigationShell.currentIndex);

    return Scaffold(
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
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
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
    );
  }
}

