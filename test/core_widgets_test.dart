import 'package:findora/core/widgets/approximate_location_note.dart';
import 'package:findora/core/widgets/show_more_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  group('ShowMoreButton', () {
    testWidgets('idle: a button that calls back', (tester) async {
      var pressed = 0;
      await pumpApp(
        tester,
        Scaffold(body: ShowMoreButton(loading: false, onPressed: () => pressed++)),
      );

      await tester.tap(find.text('Show more'));
      expect(pressed, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('loading: a spinner instead of the button', (tester) async {
      await pumpApp(
        tester,
        Scaffold(body: ShowMoreButton(loading: true, onPressed: () {})),
      );

      expect(find.text('Show more'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  testWidgets('ApproximateLocationNote tells people what others will see', (tester) async {
    await pumpApp(tester, const Scaffold(body: ApproximateLocationNote()));

    expect(find.textContaining('approximate area'), findsOneWidget);
    expect(find.textContaining('never the exact spot'), findsOneWidget);
  });
}
