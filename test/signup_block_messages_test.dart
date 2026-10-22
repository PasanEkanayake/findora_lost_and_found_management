import 'package:findora/core/auth/signup_block_messages.dart';
import 'package:findora/features/auth/signup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  group('emailCooldownMessage', () {
    test('names the date the address can be used again', () {
      final message = emailCooldownMessage(DateTime(2026, 11, 5, 12));
      expect(message, 'An account with this email was recently deleted. '
          'You can sign up with it again on Nov 5, 2026.');
    });

    test('a permanent block says the address cannot be used', () {
      expect(emailCooldownMessage(null), "This email can't be used to create an account.");
    });
  });

  group('friendlyAuthErrorMessage (what a failed Google sign-up shows)', () {
    test('the generic database error becomes the cooldown explanation', () {
      final message = friendlyAuthErrorMessage('Database error saving new user');
      expect(message, kGoogleSignupBlockedMessage);
      expect(message, contains('recently deleted'));
      expect(message, contains('waiting period'));
    });

    test('it matches the generic error however it is capitalised or wrapped', () {
      expect(friendlyAuthErrorMessage('DATABASE ERROR SAVING NEW USER'), kGoogleSignupBlockedMessage);
      expect(friendlyAuthErrorMessage('Error: database error saving new user (500)'),
          kGoogleSignupBlockedMessage);
    });

    test('the hook\'s exact message (with the date) passes through, without any prefix', () {
      const hook = 'An account with this email was recently deleted. '
          'You can sign up with it again on Nov 5, 2026.';
      expect(friendlyAuthErrorMessage(hook), hook);
      expect(friendlyAuthErrorMessage('Error from hook: $hook'), hook);
    });

    test('a permanent block from the hook passes through too', () {
      const hook = "This email can't be used to create an account.";
      expect(friendlyAuthErrorMessage('Hook error: $hook'), hook);
    });

    test('any other error is shown unchanged', () {
      expect(friendlyAuthErrorMessage('Email link is invalid or has expired'),
          'Email link is invalid or has expired');
    });
  });

  testWidgets('the sign-up page offers "Sign up with Google" below Create account', (tester) async {
    await pumpApp(tester, const SignupScreen());

    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('or'), findsOneWidget);
    // OutlinedButton.icon builds a subclass, which byType/widgetWithText skip.
    final byLabel = find.ancestor(
      of: find.text('Sign up with Google'),
      matching: find.bySubtype<OutlinedButton>(),
    );
    expect(byLabel, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
