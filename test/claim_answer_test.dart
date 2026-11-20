import 'package:findora/features/chat/widgets/claim_answer_dialog.dart';
import 'package:findora/features/items/data/claim_answer_rules.dart';
import 'package:findora/features/items/data/claim_attempt_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  group('validateClaimAnswer', () {
    test('an empty or blank answer is never accepted', () {
      expect(validateClaimAnswer('', hasQuestion: false), isNotNull);
      expect(validateClaimAnswer('     ', hasQuestion: false), isNotNull);
      expect(validateClaimAnswer('', hasQuestion: true), isNotNull);
      expect(validateClaimAnswer('  \n ', hasQuestion: true), isNotNull);
    });

    test('with no question, a real description is needed (15+ characters)', () {
      expect(validateClaimAnswer('blue wallet', hasQuestion: false), contains('at least 15'));
      expect(validateClaimAnswer('blue wallet', hasQuestion: false), contains('11 so far'));
      expect(validateClaimAnswer('a small scratch on the back', hasQuestion: false), isNull);
    });

    test('exactly the minimum passes', () {
      expect(validateClaimAnswer('a' * 15, hasQuestion: false), isNull);
      expect(validateClaimAnswer('a' * 14, hasQuestion: false), isNotNull);
    });

    test('with a question, short answers are fine ("red", "Nokia") but not one letter', () {
      expect(validateClaimAnswer('red', hasQuestion: true), isNull);
      expect(validateClaimAnswer('ok', hasQuestion: true), isNull);
      expect(validateClaimAnswer('r', hasQuestion: true), isNotNull);
    });

    test('surrounding spaces are not counted', () {
      expect(validateClaimAnswer('   short   ', hasQuestion: false), isNotNull);
      expect(validateClaimAnswer('   $kPadding   ', hasQuestion: false), isNull);
    });

    test('the same answer as before is refused, ignoring case and spaces', () {
      const earlier = 'A small scratch on the back';
      expect(
        validateClaimAnswer('  a SMALL scratch on the back ', hasQuestion: false, previousAnswer: earlier),
        contains('already tried'),
      );
      expect(
        validateClaimAnswer('A small scratch on the back and a sticker', hasQuestion: false, previousAnswer: earlier),
        isNull,
      );
      expect(validateClaimAnswer('anything long enough here', hasQuestion: false, previousAnswer: null), isNull);
    });

    test('the numbers match the database (supabase/39_claim_answer_rules.sql)', () {
      expect(kClaimMinLengthWithQuestion, 2);
      expect(kClaimMinLengthWithoutQuestion, 15);
      expect(kClaimMaxLength, 500); // claims_answer_len
    });
  });

  group('the File a claim form', () {
    Future<void> open(
      WidgetTester tester, {
      String? question,
      ClaimAttemptStatus? attempts,
      String? previousAnswer,
      void Function(String?)? onClosed,
    }) async {
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  final result = await showClaimAnswerDialog(
                    context,
                    question: question,
                    attempts: attempts,
                    previousAnswer: previousAnswer,
                  );
                  onClosed?.call(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    VoidCallback? submit(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Submit')).onPressed;

    testWidgets('Submit is disabled until the answer is a real description', (tester) async {
      await open(tester);

      expect(find.text('File a claim'), findsOneWidget);
      expect(find.textContaining('At least 15 characters'), findsOneWidget); // guidance, not an error yet
      expect(submit(tester), isNull);

      await tester.enterText(find.byType(TextField), 'blue wallet');
      await tester.pump();
      expect(submit(tester), isNull);
      expect(find.textContaining('at least 15 characters (11 so far)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'a small scratch on the back');
      await tester.pump();
      expect(submit(tester), isNotNull);
    });

    testWidgets('submitting returns the trimmed answer', (tester) async {
      String? result;
      await open(tester, onClosed: (value) => result = value);

      await tester.enterText(find.byType(TextField), '  a small scratch on the back  ');
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await settle(tester);

      expect(result, 'a small scratch on the back');
    });

    testWidgets('with a finder question: it is shown, and a short answer is enough', (tester) async {
      await open(tester, question: 'What colour is the case?');

      expect(find.text('The finder asks:'), findsOneWidget);
      expect(find.text('What colour is the case?'), findsOneWidget);
      expect(submit(tester), isNull);

      await tester.enterText(find.byType(TextField), 'red');
      await tester.pump();
      expect(submit(tester), isNotNull);
    });

    testWidgets('the same answer as the rejected one is refused with a reason', (tester) async {
      await open(tester, previousAnswer: 'a small scratch on the back');

      await tester.enterText(find.byType(TextField), 'A small scratch on the back');
      await tester.pump();

      expect(submit(tester), isNull);
      expect(find.textContaining('already tried that answer'), findsOneWidget);
    });

    testWidgets('the last attempt shows its warning inside the form', (tester) async {
      await open(
        tester,
        attempts: const ClaimAttemptStatus(attemptsUsed: 2, maxAttempts: 3),
      );

      expect(find.textContaining('This is your last attempt (3 of 3)'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('tapping outside does not throw the answer away', (tester) async {
      var closed = false;
      await open(tester, onClosed: (_) => closed = true);

      await tester.enterText(find.byType(TextField), 'a small scratch on the back');
      await tester.tapAt(const Offset(5, 5)); // the dimmed area outside the dialog
      await settle(tester);

      expect(find.text('File a claim'), findsOneWidget);
      expect(closed, isFalse);
    });

    testWidgets('Cancel closes it and returns nothing', (tester) async {
      String? result = 'unset';
      await open(tester, onClosed: (value) => result = value);

      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(result, isNull);
      expect(find.text('File a claim'), findsNothing);
    });

    testWidgets('a long question and warning scroll instead of overflowing a small screen',
        (tester) async {
      tester.view.physicalSize = const Size(360, 520);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await open(
        tester,
        question: 'Describe the inside of the bag, including everything you remember: ' * 3,
        attempts: const ClaimAttemptStatus(attemptsUsed: 2, maxAttempts: 3),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Submit'), findsOneWidget);
    });
  });
}

/// 15 characters of padding for the "spaces are not counted" test.
const kPadding = 'fifteen letters';
