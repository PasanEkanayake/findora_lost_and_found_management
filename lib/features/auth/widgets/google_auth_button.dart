import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';

/// "Continue with Google" / "Sign up with Google" — used on both the sign-in
/// and the sign-up screens (Google has no separate "sign up": a first-time
/// Google sign-in creates the account, and the app then shows its
/// "You're signed up!" step).
///
/// Opens the browser; the person comes back through the
/// `io.supabase.findora://login-callback` link. If that fails — for example
/// the address belongs to an account deleted in the last 14 days — the app
/// shows the reason (see core/auth/auth_error_notifier.dart).
class GoogleAuthButton extends StatelessWidget {
  const GoogleAuthButton({super.key, required this.label});

  final String label;

  Future<void> _signIn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      // Needs the redirect URL registered in the Supabase dashboard
      // (Authentication > URL Configuration) and as a native URL scheme — see
      // README.md, "Google sign-in setup".
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.findora://login-callback',
      );
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: errorColor));
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _signIn(context),
      icon: const Icon(Icons.g_mobiledata, size: 28),
      label: Text(label),
    );
  }
}
