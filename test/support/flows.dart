import 'package:findora/core/connectivity/connectivity_provider.dart';
import 'package:findora/core/widgets/offline_banner.dart';
import 'package:findora/features/chat/data/safety_providers.dart';
import 'package:findora/features/items/data/items_providers.dart';
import 'package:findora/features/matches/data/match_model.dart';
import 'package:findora/features/matches/data/matches_providers.dart';
import 'package:findora/features/matches/matches_screen.dart';
import 'package:findora/features/matches/widgets/match_card.dart';
import 'package:findora/features/profile/admin_reports_screen.dart';
import 'package:findora/features/profile/data/appeal_model.dart';
import 'package:findora/features/profile/data/moderated_item_model.dart';
import 'package:findora/features/profile/data/moderation_log_entry.dart';
import 'package:findora/features/profile/data/profile_providers.dart';
import 'package:findora/features/profile/data/report_model.dart';
import 'package:findora/features/profile/hidden_posts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fake_matches_repository.dart';
import 'fake_moderation_repositories.dart';
import 'test_app.dart';

/// The main user flows, written once and run twice: as fast widget tests
/// (`flutter test`) and on a device (`flutter test integration_test`), where
/// they check the same behaviour on a real screen and engine.
///
/// Each flow drives a REAL screen against in-memory fakes of the repositories
/// (see test_app.dart for why the whole app can't be started). Pass
/// `resizeView: false` on a device.

// ---------------------------------------------------------------------------
// Matches
// ---------------------------------------------------------------------------

List<Override> matchesOverrides(FakeMatchesRepository repo) => [
      matchesRepositoryProvider.overrideWithValue(repo),
      itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
      blockedUserIdsProvider.overrideWith((ref) async => <String>{}),
    ];

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await settle(tester);
}

/// A match is only confirmed when BOTH people confirm: my "This is it!" moves
/// it to "Waiting for the other person", I can take it back, and the chat
/// (the Message button) appears only once the other person confirms too.
Future<void> twoSidedConfirmationFlow(WidgetTester tester, {bool resizeView = true}) async {
  final repo = FakeMatchesRepository([FakeMatch(id: 'm1', title: 'Found brown wallet')]);
  final container =
      await pumpApp(tester, const MatchesScreen(), overrides: matchesOverrides(repo), resizeView: resizeView);

  // 1. A fresh match needs my input.
  expect(find.text('Needs your input'), findsOneWidget);
  expect(find.text('Found brown wallet'), findsOneWidget);
  expect(find.text('This is it!'), findsOneWidget);
  expect(find.text('Not a match'), findsOneWidget);
  expect(find.text('Waiting for the other person'), findsNothing);

  // 2. I confirm: it waits for the other person — no chat yet.
  await tapText(tester, 'This is it!');
  expect(repo.decisions.last, (matchId: 'm1', decision: 'confirmed'));
  expect(find.text('Waiting for the other person'), findsOneWidget);
  expect(find.text('You confirmed. The chat opens once the other person confirms too.'),
      findsOneWidget);
  expect(find.text('Needs your input'), findsNothing);
  expect(find.text('Message'), findsNothing);

  // 3. I change my mind: back to needing my input.
  await tapText(tester, 'Undo my confirmation');
  expect(repo.decisions.last, (matchId: 'm1', decision: 'pending'));
  expect(find.text('Needs your input'), findsOneWidget);
  expect(find.text('Waiting for the other person'), findsNothing);

  // 4. Confirm again, then the other person confirms on their phone.
  await tapText(tester, 'This is it!');
  expect(find.text('Waiting for the other person'), findsOneWidget);
  repo.otherDecides('m1', 'confirmed');
  container.invalidate(matchesProvider); // what the app's 15-second refresh does
  await settle(tester);

  // 5. Mutual: the match is decided and the chat button appears.
  expect(find.text('Already decided'), findsOneWidget);
  expect(find.text('Message'), findsOneWidget);
  expect(find.text('Waiting for the other person'), findsNothing);
}

/// The other person confirmed first: the card says so, and my "This is it!"
/// makes it mutual straight away.
Future<void> otherConfirmedFirstFlow(WidgetTester tester, {bool resizeView = true}) async {
  final repo = FakeMatchesRepository([
    FakeMatch(id: 'm1', title: 'Found brown wallet', otherDecision: 'confirmed'),
  ]);
  await pumpApp(tester, const MatchesScreen(), overrides: matchesOverrides(repo), resizeView: resizeView);

  expect(find.text('The other person says this is a match. Confirm too to start chatting.'),
      findsOneWidget);
  await tapText(tester, 'This is it!');

  expect(find.text("It's mutual — you can message each other now."), findsOneWidget);
  expect(find.text('Already decided'), findsOneWidget);
  expect(find.text('Message'), findsOneWidget);
}

/// "Not a match" ends it; Undo (while it's my own dismissal) brings it back.
Future<void> dismissAndUndoFlow(WidgetTester tester, {bool resizeView = true}) async {
  final repo = FakeMatchesRepository([FakeMatch(id: 'm1', title: 'Found brown wallet')]);
  await pumpApp(tester, const MatchesScreen(), overrides: matchesOverrides(repo), resizeView: resizeView);

  await tapText(tester, 'Not a match');
  expect(find.text('Marked as not a match.'), findsOneWidget);
  expect(find.text('Already decided'), findsOneWidget);
  expect(find.text('Dismissed'), findsOneWidget);
  expect(find.text('This is it!'), findsNothing);

  // The card's own Undo (the snackbar has one too, labelled the same).
  await tester.tap(find.descendant(of: find.byType(MatchCard), matching: find.text('Undo')));
  await settle(tester);
  expect(find.text('Needs your input'), findsOneWidget);
  expect(find.text('Dismissed'), findsNothing);
}

/// 25 matches show 20, then "Show more" asks for 40 and reveals the rest.
Future<void> matchesPagingFlow(WidgetTester tester, {bool resizeView = true}) async {
  String two(int n) => n.toString().padLeft(2, '0');
  final repo = FakeMatchesRepository([
    for (var i = 1; i <= 25; i++)
      FakeMatch(id: 'm$i', title: 'Found item ${two(i)}', score: 0.99 - i * 0.01),
  ]);
  await pumpApp(tester, const MatchesScreen(), overrides: matchesOverrides(repo), resizeView: resizeView);

  int pendingLimit() => repo.requests.where((r) => r.section == 'pending').last.limit;

  expect(find.text('Found item 01'), findsOneWidget);
  expect(pendingLimit(), 20);

  await tester.scrollUntilVisible(find.text('Show more'), 600, scrollable: verticalList());
  expect(find.text('Found item 25'), findsNothing); // not loaded yet

  await tapText(tester, 'Show more');
  expect(pendingLimit(), 40);
  await tester.scrollUntilVisible(find.text('Found item 25'), 600, scrollable: verticalList());
  expect(find.text('Found item 25'), findsOneWidget);
  expect(find.text('Show more'), findsNothing); // everything is loaded
}

/// A filter chip is sent to the server (the list is paged, so it can't be
/// applied to what happens to be loaded) and resets paging.
Future<void> matchesFilterFlow(WidgetTester tester, {bool resizeView = true}) async {
  final repo = FakeMatchesRepository([FakeMatch(id: 'm1', title: 'Found brown wallet')])
    ..emptyWhenFiltered = true;
  await pumpApp(tester, const MatchesScreen(), overrides: matchesOverrides(repo), resizeView: resizeView);

  await tapText(tester, '📝 Text only');
  expect(repo.requests.last.filter, MatchFilter.textOnly);
  expect(repo.requests.last.limit, 20);
  expect(find.text('No matches with this filter'), findsOneWidget);

  await tapText(tester, 'All');
  expect(repo.requests.last.filter, MatchFilter.all);
  expect(find.text('Found brown wallet'), findsOneWidget);
}

// ---------------------------------------------------------------------------
// Offline banner
// ---------------------------------------------------------------------------

class _DraftScreen extends StatefulWidget {
  const _DraftScreen();

  @override
  State<_DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends State<_DraftScreen> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Draft')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(key: const ValueKey('draft'), controller: controller),
      ),
    );
  }
}

/// The banner appears when the connection drops, says "Back online" briefly
/// when it returns, and — importantly — never rebuilds the screens under it,
/// so a half-typed message survives the whole thing.
Future<void> offlineBannerFlow(WidgetTester tester, {bool resizeView = true}) async {
  const offlineText = "You're offline — showing what's already loaded";
  final container = await pumpApp(
    tester,
    const _DraftScreen(),
    overrides: [connectivityProvider.overrideWith(FakeConnectivity.new)],
    builder: (context, child) => OfflineBannerHost(child: child ?? const SizedBox.shrink()),
    resizeView: resizeView,
  );
  final fake = container.read(connectivityProvider.notifier) as FakeConnectivity;

  await tester.enterText(find.byKey(const ValueKey('draft')), 'half-written message');
  expect(find.text(offlineText), findsNothing);

  fake.setOnline(false);
  await settle(tester);
  expect(find.text(offlineText), findsOneWidget);
  expect(tester.widget<TextField>(find.byKey(const ValueKey('draft'))).controller!.text,
      'half-written message');

  fake.setOnline(true);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Back online'), findsOneWidget);
  expect(find.text(offlineText), findsNothing);

  await tester.pump(const Duration(seconds: 3)); // the green banner goes away by itself
  await settle(tester);
  expect(find.text('Back online'), findsNothing);
  expect(tester.widget<TextField>(find.byKey(const ValueKey('draft'))).controller!.text,
      'half-written message');
}

// ---------------------------------------------------------------------------
// Moderation: the admin queue and the owner's appeal
// ---------------------------------------------------------------------------

Finder inDialog(Finder finder) =>
    find.descendant(of: find.byType(AlertDialog), matching: finder);

Future<void> enterDialogText(WidgetTester tester, String text) async {
  await tester.enterText(inDialog(find.byType(TextField)), text);
  await tester.pump();
}

VoidCallback? onPressedOf(WidgetTester tester, Finder button) =>
    tester.widget<FilledButton>(button).onPressed;

/// An admin works the queue: restores an auto-hidden post, removes another,
/// denies one appeal (a reason is required) and upholds another, then finds it
/// all in the activity log.
Future<void> adminModerationFlow(WidgetTester tester, {bool resizeView = true}) async {
  final repo = FakeAdminRepository(
    reports: [
      ReportModel(
        id: 'r1',
        itemId: 'i1',
        itemTitle: 'Black wallet',
        reason: 'spam',
        status: 'open',
        createdAt: DateTime(2026, 10, 1),
        itemModerationState: 'auto_hidden',
      ),
      ReportModel(
        id: 'r2',
        itemId: 'i2',
        itemTitle: 'Blue bottle',
        reason: 'scam',
        status: 'open',
        createdAt: DateTime(2026, 10, 2),
      ),
    ],
    appeals: [
      AppealModel(
        id: 'a1',
        itemId: 'i3',
        itemTitle: 'Red scarf',
        ownerName: 'Sam Lee',
        message: 'This is my own scarf, I posted it yesterday.',
        createdAt: DateTime(2026, 10, 3),
        itemModerationState: 'auto_hidden',
      ),
      AppealModel(
        id: 'a2',
        itemId: 'i4',
        itemTitle: 'Green hat',
        ownerName: 'Ana Perera',
        message: 'The report was about a different hat.',
        createdAt: DateTime(2026, 10, 4),
        itemModerationState: 'removed',
      ),
    ],
    log: [
      ModerationLogEntry(
        id: 2,
        createdAt: DateTime(2026, 10, 2),
        actorKind: 'admin',
        actorName: 'Alex',
        action: 'item_removed',
        itemTitle: 'Blue bottle',
        note: 'Looked like a scam',
      ),
      ModerationLogEntry(
        id: 1,
        createdAt: DateTime(2026, 10, 1),
        actorKind: 'system',
        action: 'auto_hidden',
        itemTitle: 'Black wallet',
      ),
    ],
  );
  await pumpApp(
    tester,
    const AdminReportsScreen(),
    overrides: [adminRepositoryProvider.overrideWithValue(repo)],
    resizeView: resizeView,
  );

  // Posts tab: the auto-hidden one is labelled and offers Restore.
  expect(find.text('Hidden automatically after several reports'), findsOneWidget);
  expect(find.text('Restore post'), findsOneWidget);

  await tapText(tester, 'Restore post');
  expect(find.text('Restore this post?'), findsOneWidget);
  await enterDialogText(tester, 'Looks fine');
  await tester.tap(inDialog(find.text('Restore')));
  await settle(tester);
  expect(repo.actions, contains('restore i1 | Looks fine'));
  expect(find.text('Hidden automatically after several reports'), findsNothing);

  await tapText(tester, 'Remove post');
  expect(find.text('Remove this post?'), findsOneWidget);
  await tester.tap(inDialog(find.text('Remove'))); // the note is optional here
  await settle(tester);
  expect(repo.actions, contains('remove i2 | '));
  expect(find.text('No open reports.'), findsOneWidget);

  // Appeals tab: a denial needs a reason.
  await tapText(tester, 'Appeals');
  expect(find.text('Red scarf'), findsOneWidget);
  expect(find.text('This is my own scarf, I posted it yesterday.'), findsOneWidget);

  await tester.tap(find.text('Deny').first);
  await settle(tester);
  expect(find.text('Deny this appeal?'), findsOneWidget);
  final denyButton = find.widgetWithText(FilledButton, 'Deny appeal');
  expect(onPressedOf(tester, denyButton), isNull);
  await enterDialogText(tester, 'ab');
  expect(onPressedOf(tester, denyButton), isNull);
  await enterDialogText(tester, 'Contains a phone number');
  expect(onPressedOf(tester, denyButton), isNotNull);
  await tester.tap(denyButton);
  await settle(tester);
  expect(repo.actions, contains('appeal a1 denied | Contains a phone number'));
  expect(find.text('Red scarf'), findsNothing);

  // The other appeal is accepted (no note needed).
  expect(find.text('Green hat'), findsOneWidget);
  await tapText(tester, 'Restore post');
  await tester.tap(inDialog(find.text('Restore')));
  await settle(tester);
  expect(repo.actions, contains('appeal a2 upheld | '));
  expect(find.text('No open appeals.'), findsOneWidget);

  // Activity tab: the log, newest first, with who did it.
  await tapText(tester, 'Activity');
  expect(find.text('Post removed'), findsOneWidget);
  expect(find.text('Post hidden automatically after several reports'), findsOneWidget);
  expect(find.textContaining('Alex'), findsOneWidget);
  expect(find.text('Note: Looked like a scam'), findsOneWidget);
  expect(find.textContaining('The system'), findsOneWidget);
}

/// An owner sees why a post is hidden and appeals it — but only with a real
/// explanation, and only once.
Future<void> ownerAppealFlow(WidgetTester tester, {bool resizeView = true}) async {
  final repo = FakeModerationRepository([
    ModeratedItemModel(
      itemId: 'i1',
      title: 'Black wallet',
      itemType: 'lost',
      moderationState: 'auto_hidden',
      moderatedAt: DateTime(2026, 10, 1, 10),
    ),
    ModeratedItemModel(
      itemId: 'i2',
      title: 'Blue bottle',
      itemType: 'found',
      moderationState: 'removed',
      moderatedAt: DateTime(2026, 9, 28, 10),
      appealStatus: 'denied',
      appealNote: 'Contains a phone number.',
      canAppeal: false,
    ),
  ]);
  await pumpApp(
    tester,
    const HiddenPostsScreen(),
    overrides: [moderationRepositoryProvider.overrideWithValue(repo)],
    resizeView: resizeView,
  );

  expect(find.text('Hidden after several people reported it'), findsOneWidget);
  expect(find.text('Removed by a moderator'), findsOneWidget);
  expect(find.text('Appeal denied: Contains a phone number. This decision is final.'),
      findsOneWidget);
  // Only the post that can still be appealed offers the button.
  // (FilledButton.icon builds a subclass, which byType/widgetWithText skip.)
  final appealButton =
      find.ancestor(of: find.text('Appeal'), matching: find.bySubtype<FilledButton>());
  expect(appealButton, findsOneWidget);

  await tester.tap(appealButton);
  await settle(tester);
  expect(find.text('Appeal this decision'), findsOneWidget);
  final send = find.widgetWithText(FilledButton, 'Send appeal');
  expect(onPressedOf(tester, send), isNull);
  await enterDialogText(tester, 'too short'); // 9 characters
  expect(onPressedOf(tester, send), isNull);
  await enterDialogText(tester, 'This is my own wallet, I lost it on Monday.');
  expect(onPressedOf(tester, send), isNotNull);

  await tester.tap(send);
  await settle(tester);

  expect(repo.appeals, [
    (itemId: 'i1', message: 'This is my own wallet, I lost it on Monday.'),
  ]);
  expect(find.text("Appeal sent — we'll review it and let you know."), findsOneWidget);
  expect(appealButton, findsNothing); // one appeal per hiding
}
