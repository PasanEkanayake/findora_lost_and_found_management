// The original template test here pumped the app and looked for a counter —
// that came with `flutter create` and could never pass (the app needs Supabase
// and Firebase to start, and has no counter). It is replaced by real checks of
// the chat safety helpers; the other tests live in the sibling files:
//   match_tier_test.dart, feed_paging_test.dart.
import 'package:findora/core/errors/friendly_error.dart';
import 'package:findora/features/chat/widgets/safe_send.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('looksLikePhoneNumber', () {
    test('detects common phone formats', () {
      expect(looksLikePhoneNumber('call me on 0771234567'), isTrue);
      expect(looksLikePhoneNumber('+94 77 123 4567'), isTrue);
      expect(looksLikePhoneNumber('(077) 123-4567 after 5'), isTrue);
    });

    test('ignores ordinary text, short numbers, and IMEI-length numbers', () {
      expect(looksLikePhoneNumber('I found it near gate 12'), isFalse);
      expect(looksLikePhoneNumber('serial 123456'), isFalse);
      expect(looksLikePhoneNumber('IMEI is 356938035643809'), isFalse);
      expect(looksLikePhoneNumber(''), isFalse);
    });
  });

  group('friendlyDatabaseError', () {
    test('shows our own limit and refusal messages', () {
      expect(
        friendlyDatabaseError(
          PostgrestException(message: 'Posting limit reached.', code: 'RL001'),
          fallback: 'fallback',
        ),
        'Posting limit reached.',
      );
      expect(
        friendlyDatabaseError(
          PostgrestException(message: 'A claim has already been filed.', code: '22023'),
          fallback: 'fallback',
        ),
        'A claim has already been filed.',
      );
    });

    test('hides everything else behind the fallback', () {
      expect(
        friendlyDatabaseError(
          PostgrestException(message: 'new row violates row-level security policy', code: '42501'),
          fallback: 'Try again.',
        ),
        'Try again.',
      );
      expect(friendlyDatabaseError(Exception('socket closed'), fallback: 'Try again.'), 'Try again.');
    });
  });
}
