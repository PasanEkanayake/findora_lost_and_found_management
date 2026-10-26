import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../supabase/supabase_client.dart';
import 'signup_block_messages.dart';

/// Attached to the MaterialApp so a message can be shown from anywhere, even
/// when the screen that started the action is gone.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Shows a message when a sign-in that went through the browser FAILS.
///
/// "Continue with Google" opens a browser and returns through a link. If it
/// comes back with an error — the address is still in its waiting period after
/// an account deletion, the link expired, the person said no — Supabase reports
/// it on the auth stream as an error, and without this nobody would ever see
/// it: the app would just sit on the sign-in screen. (An email/password
/// sign-in reports its own errors on the spot.)
///
/// Watched once from the app root (see main.dart). The value is unused.
final authErrorNoticeProvider = Provider<void>((ref) {
  final subscription = supabase.auth.onAuthStateChange.listen(
    (_) {},
    onError: (Object error) {
      if (error is! AuthException) return;
      final message = friendlyAuthErrorMessage(error.message).trim();
      if (message.isEmpty) return;
      rootScaffoldMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
        );
    },
  );
  ref.onDispose(subscription.cancel);
});
