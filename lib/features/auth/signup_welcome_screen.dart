import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/auth_providers.dart';
import '../../core/supabase/supabase_client.dart';

/// Shown once, right after a Google sign-in the router's redirect (see
/// app_router.dart) determined looks like a brand-new account — see
/// looksLikeFreshOAuthSignup's doc in auth_providers.dart for exactly
/// what "looks like" means and why this can't be a true pre-signup
/// confirmation (Supabase's OAuth flow already created the account by
/// the time the app regains control).
///
/// Framed honestly around that constraint: this doesn't offer to
/// "cancel" account creation (the client has no way to actually delete
/// the account it can't undo), just to continue into the app or sign
/// back out if this wasn't the intended account.
class SignupWelcomeScreen extends ConsumerWidget {
  const SignupWelcomeScreen({super.key});

  Future<void> _continue(WidgetRef ref, BuildContext context) async {
    ref.read(signupWelcomeSeenProvider.notifier).markSeen();
    if (context.mounted) context.go('/feed');
  }

  Future<void> _notMe(WidgetRef ref, BuildContext context) async {
    ref.read(signupWelcomeSeenProvider.notifier).markSeen();
    await supabase.auth.signOut();
    // The router's redirect sends a signed-out session to /login on its
    // own once onAuthStateChange fires from signOut() above — no
    // explicit navigation needed here.
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final email = user?.email ?? user?.userMetadata?['email'] as String? ?? 'your Google account';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.celebration_outlined,
                  size: 40,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "You're signed up!",
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                "This looks like the first time $email has signed in — "
                "we've created your Findora account with it.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => _continue(ref, context),
                child: const Text('Continue to Findora'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _notMe(ref, context),
                child: const Text("Not me — sign out"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
