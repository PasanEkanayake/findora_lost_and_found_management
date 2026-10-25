import 'package:findora/features/home/feed_filter_sheet.dart';
import 'package:findora/features/items/data/feed_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

/// Regression test for "the filter button opens only a transparent screen".
///
/// The app theme makes every FilledButton full-width; an unstyled one inside
/// a Row (the sheet's "Apply") has an infinite minimum width, Flutter throws a
/// layout error, and a release build then paints nothing but the backdrop. The
/// test harness uses the same button rules (testTheme), so that fails here.
void main() {
  Future<FeedFilterResult?> openSheet(
    WidgetTester tester, {
    String? saveDescription = '"wallet" · Found posts',
  }) async {
    FeedFilterResult? result;
    var closed = false;
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                result = await showFeedFilterSheet(
                  context,
                  window: FeedWindow.any,
                  sort: FeedSort.newest,
                  saveDescription: saveDescription,
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'the sheet must lay out without errors');
    expect(closed, isFalse);
    return result;
  }

  testWidgets('the sheet actually shows its controls', (tester) async {
    await openSheet(tester);

    expect(find.text('Filter & sort'), findsOneWidget);
    expect(find.text('Posted'), findsOneWidget);
    expect(find.text('Newest first'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Save this search'), findsOneWidget);
    expect(find.text('Saved searches'), findsOneWidget);
  });

  testWidgets('Apply closes it with the chosen options', (tester) async {
    FeedFilterResult? result;
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showFeedFilterSheet(
                context,
                window: FeedWindow.any,
                sort: FeedSort.newest,
                saveDescription: null,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);

    await tester.tap(find.text('Last 7 days'));
    await tester.pump();
    await tester.tap(find.text('Oldest first'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await settle(tester);

    expect(result?.window, FeedWindow.week);
    expect(result?.sort, FeedSort.oldest);
    expect(result?.action, FeedFilterAction.apply);
  });

  testWidgets('nothing to save yet: explains how, and offers no Save button', (tester) async {
    await openSheet(tester, saveDescription: null);

    expect(find.text('Save this search'), findsNothing);
    expect(find.textContaining('Type a search, or pick a category'), findsOneWidget);
    expect(find.text('Saved searches'), findsOneWidget); // the list is always reachable
  });

  testWidgets('Saved searches and Save this search close it with those actions', (tester) async {
    for (final entry in {
      'Saved searches': FeedFilterAction.manage,
      'Save this search': FeedFilterAction.save,
    }.entries) {
      FeedFilterResult? result;
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showFeedFilterSheet(
                  context,
                  window: FeedWindow.any,
                  sort: FeedSort.newest,
                  saveDescription: '"wallet"',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.text(entry.key));
      await settle(tester);
      expect(result?.action, entry.value, reason: entry.key);
    }
  });
}
