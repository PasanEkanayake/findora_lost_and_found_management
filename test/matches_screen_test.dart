import 'package:findora/features/matches/matches_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_matches_repository.dart';
import 'support/flows.dart';
import 'support/test_app.dart';

/// The Matches tab, driven against an in-memory stand-in for the database that
/// follows the same two-sided confirmation rules (see support/).
void main() {
  testWidgets('two-sided confirmation: confirm, wait, undo, mutual', (tester) async {
    await twoSidedConfirmationFlow(tester);
  });

  testWidgets('the other person confirmed first: my confirm makes it mutual', (tester) async {
    await otherConfirmedFirstFlow(tester);
  });

  testWidgets('Not a match dismisses it, and Undo brings it back', (tester) async {
    await dismissAndUndoFlow(tester);
  });

  testWidgets('a long list shows 20, then Show more loads the rest', (tester) async {
    await matchesPagingFlow(tester);
  });

  testWidgets('filter chips are sent to the server and reset paging', (tester) async {
    await matchesFilterFlow(tester);
  });

  testWidgets('no matches at all: the explanatory empty state, no filter chips', (tester) async {
    final repo = FakeMatchesRepository([]);
    await pumpApp(tester, const MatchesScreen(), overrides: matchesOverrides(repo));

    expect(find.text('No matches yet'), findsOneWidget);
    expect(find.text('📝 Text only'), findsNothing);
  });

  testWidgets('dismissed by the other person: no Undo to offer', (tester) async {
    final repo = FakeMatchesRepository([
      FakeMatch(id: 'm1', title: 'Found brown wallet', otherDecision: 'dismissed'),
    ]);
    await pumpApp(tester, const MatchesScreen(), overrides: matchesOverrides(repo));

    expect(find.text('Already decided'), findsOneWidget);
    expect(find.text('Dismissed'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('This is it!'), findsNothing);
  });

  testWidgets('a match I confirmed waits in its own section, not under "Needs your input"',
      (tester) async {
    final repo = FakeMatchesRepository([
      FakeMatch(id: 'm1', title: 'Waiting wallet', myDecision: 'confirmed'),
      FakeMatch(id: 'm2', title: 'Fresh wallet'),
    ]);
    await pumpApp(tester, const MatchesScreen(), overrides: matchesOverrides(repo));

    expect(find.text('Needs your input'), findsOneWidget);
    expect(find.text('Waiting for the other person'), findsOneWidget);
    expect(find.text('Fresh wallet'), findsOneWidget);
    expect(find.text('Waiting wallet'), findsOneWidget);
    expect(find.text('This is it!'), findsOneWidget); // only the fresh one asks
  });
}
