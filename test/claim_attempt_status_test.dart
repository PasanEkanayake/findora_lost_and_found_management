import 'package:findora/features/items/data/claim_attempt_status.dart';
import 'package:findora/features/items/widgets/claim_attempt_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  final now = DateTime(2026, 10, 20, 12, 0);

  ClaimAttemptStatus status({int used = 0, int max = 3, DateTime? retryAt, bool live = false}) =>
      ClaimAttemptStatus(attemptsUsed: used, maxAttempts: max, retryAt: retryAt, hasLiveClaim: live);

  group('counts', () {
    test('attempts left, locked and last attempt', () {
      expect(status(used: 0).attemptsLeft, 3);
      expect(status(used: 2).attemptsLeft, 1);
      expect(status(used: 2).isLastAttempt, isTrue);
      expect(status(used: 1).isLastAttempt, isFalse);
      expect(status(used: 3).isLocked, isTrue);
      expect(status(used: 3).attemptsLeft, 0);
    });

    test('more used than allowed never goes negative', () {
      expect(status(used: 5).attemptsLeft, 0);
      expect(status(used: 5).isLocked, isTrue);
    });

    test('the next attempt number', () {
      expect(status(used: 0).nextAttemptNumber, 1);
      expect(status(used: 2).nextAttemptNumber, 3);
    });
  });

  group('waitMinutes', () {
    test('rounds up, at least a minute', () {
      expect(status(used: 1, retryAt: now.add(const Duration(minutes: 42))).waitMinutes(now: now), 42);
      expect(status(used: 1, retryAt: now.add(const Duration(seconds: 61))).waitMinutes(now: now), 2);
      expect(status(used: 1, retryAt: now.add(const Duration(seconds: 5))).waitMinutes(now: now), 1);
    });

    test('no wait when none is set, or it already ended', () {
      expect(status(used: 1).waitMinutes(now: now), isNull);
      expect(status(used: 1, retryAt: now.subtract(const Duration(minutes: 1))).waitMinutes(now: now),
          isNull);
    });

    test('no wait is reported once the attempts are gone — locked says it all', () {
      expect(status(used: 3, retryAt: now.add(const Duration(hours: 1))).waitMinutes(now: now), isNull);
    });
  });

  test('fromMap reads the database row', () {
    final s = ClaimAttemptStatus.fromMap({
      'attempts_used': 2,
      'max_attempts': 3,
      'attempts_left': 1,
      'has_live_claim': false,
      'retry_at': '2026-10-20T13:00:00+00:00',
    });
    expect(s.attemptsUsed, 2);
    expect(s.maxAttempts, 3);
    expect(s.retryAt, isNotNull);
    expect(ClaimAttemptStatus.fromMap({'attempts_used': 0, 'max_attempts': 3}).retryAt, isNull);
  });

  group('the warning on the claim form (BEFORE the limit)', () {
    test('first attempt: says how many tries there are', () {
      expect(claimDialogWarning(status(used: 0)),
          "You have 3 attempts for this post. If a claim isn't approved you can try again after a short wait.");
    });

    test('middle attempt: which one, and what a rejection leaves', () {
      expect(claimDialogWarning(status(used: 1)),
          "Attempt 2 of 3. If it isn't approved you'll have 1 attempt left.");
    });

    test('last attempt: an explicit warning', () {
      expect(claimDialogWarning(status(used: 2)),
          "This is your last attempt (3 of 3). If it isn't approved you won't be able to claim this post again.");
    });

    test('nothing to say once locked', () {
      expect(claimDialogWarning(status(used: 3)), isNull);
    });
  });

  group('the banner after a rejection', () {
    test('attempts left and no wait', () {
      expect(claimRejectedMessage(status(used: 1), now: now),
          "That claim wasn't approved. You have 2 attempts left.");
    });

    test('while waiting: how long, and what is left', () {
      expect(
        claimRejectedMessage(status(used: 1, retryAt: now.add(const Duration(minutes: 42))), now: now),
        "That claim wasn't approved. You can try again in about 42 minutes. You have 2 attempts left.",
      );
      expect(
        claimRejectedMessage(status(used: 1, retryAt: now.add(const Duration(minutes: 1))), now: now),
        contains('about 1 minute.'),
      );
    });

    test('one attempt left: warns it is the last', () {
      final message = claimRejectedMessage(status(used: 2), now: now);
      expect(message, contains('1 attempt left'));
      expect(message, contains('your last'));
    });

    test('AT the limit: says it can no longer be claimed, and points to support', () {
      final message = claimRejectedMessage(status(used: 3), now: now);
      expect(message, contains('used all 3 attempts'));
      expect(message, contains("can't be claimed again"));
      expect(message, contains('contact support'));
    });
  });

  test('the intro before any claim states the limit', () {
    expect(claimAttemptsIntro(status()), contains('up to 3 times for each post'));
  });

  group('ClaimAttemptNotice', () {
    testWidgets('shows its message; the last attempt is styled as a warning', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: Column(
            children: [
              ClaimAttemptNotice(message: 'Attempt 2 of 3.'),
              ClaimAttemptNotice(message: 'This is your last attempt.', urgent: true),
            ],
          ),
        ),
      );

      expect(find.text('Attempt 2 of 3.'), findsOneWidget);
      expect(find.text('This is your last attempt.'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });
}
