import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client.dart';

/// Emits on every auth state change (sign in, sign out, token refresh,
/// etc.). Riverpod's StreamProvider keeps exactly one subscription alive
/// for as long as anything is watching it, so the router, the profile
/// screen, and anything added in later phases all react to the same
/// underlying stream instead of each opening their own.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// Convenience accessor for the currently signed-in user, or null.
/// Re-evaluates whenever [authStateChangesProvider] emits — screens should
/// watch this instead of reading `supabase.auth.currentUser` directly, or
/// they won't rebuild when the session changes.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateChangesProvider);
  return supabase.auth.currentUser;
});

/// True if [user] appears to have just been created via an OAuth
/// provider (Google) this same sign-in — used to route a first-time
/// Google sign-in through SignupWelcomeScreen instead of straight to
/// /feed. Email/password signup isn't covered here: it already has its
/// own explicit "Sign up" form the person deliberately filled out, so
/// there's no ambiguity to resolve the way "Continue with Google" alone
/// has (that one button covers both login *and* signup, with nothing in
/// the UI distinguishing which one just happened).
///
/// Supabase's OAuth flow creates the `auth.users` row automatically on
/// first sign-in — there's no separate "confirm before creating the
/// account" step the client can hook into before that happens, since
/// sign-in and sign-up are the same action for OAuth providers by design
/// (true of "Sign in with Google/Apple" everywhere, not a Findora
/// limitation). This heuristic is what's achievable after the fact
/// instead: [User.createdAt] and [User.lastSignInAt] are set from the
/// exact same OAuth callback for a brand-new account, so they land
/// within a second or two of each other; a returning user's `createdAt`
/// stays fixed from their original signup while `lastSignInAt` updates
/// to now, so the two diverge by far more than that.
bool looksLikeFreshOAuthSignup(User user) {
  final isOAuth = user.appMetadata['provider'] != 'email';
  if (!isOAuth) return false;

  final createdAt = DateTime.tryParse(user.createdAt);
  final lastSignInAtRaw = user.lastSignInAt;
  final lastSignInAt = lastSignInAtRaw == null ? null : DateTime.tryParse(lastSignInAtRaw);
  if (createdAt == null || lastSignInAt == null) return false;

  return lastSignInAt.difference(createdAt).abs() < const Duration(seconds: 15);
}

/// Set once the person taps through SignupWelcomeScreen, so the router's
/// redirect (which re-runs on every navigation, not just once) doesn't
/// keep sending them back to it for the rest of this same fresh-signup
/// session — [looksLikeFreshOAuthSignup] stays true for longer than one
/// screen, since the account's timestamps don't change just because they
/// moved on. Deliberately in-memory only (not persisted): the whole
/// point is "have they seen it yet this signup", and a real subsequent
/// sign-in is a different session where the heuristic above naturally
/// reads false anyway (see its own doc).
class SignupWelcomeSeenController extends Notifier<bool> {
  @override
  bool build() => false;

  void markSeen() => state = true;
}

final signupWelcomeSeenProvider = NotifierProvider<SignupWelcomeSeenController, bool>(
  SignupWelcomeSeenController.new,
);
