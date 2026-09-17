import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';

/// Email/password + Google sign-in. On success there's deliberately no
/// manual navigation here — the router's `redirect` callback (see
/// core/router/app_router.dart) reacts to the auth state change and sends
/// signed-in users to /feed on its own, from wherever they were.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? theme.colorScheme.error : null,
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      if (_isEmailNotConfirmedError(e)) {
        _showEmailNotConfirmedMessage();
      } else {
        _showMessage(e.message, isError: true);
      }
    } catch (_) {
      _showMessage(
        'Something went wrong. Check your connection and try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Matched on the message text rather than a specific error code, since
  /// that's stable across supabase_flutter versions — this is a standard
  /// GoTrue response whenever "Confirm email" is enabled for the project
  /// (Supabase Dashboard → Authentication → Providers → Email) and the
  /// account hasn't clicked the link yet. It isn't a bug in the app; it's
  /// the intended behavior of that setting.
  bool _isEmailNotConfirmedError(AuthException e) {
    return e.message.toLowerCase().contains('email not confirmed') ||
        e.message.toLowerCase().contains('email_not_confirmed');
  }

  void _showEmailNotConfirmedMessage() {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "Your email isn't confirmed yet. Check your inbox (and spam "
          'folder) for the link, or resend it.',
        ),
        backgroundColor: theme.colorScheme.error,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Resend',
          onPressed: _resendConfirmationEmail,
        ),
      ),
    );
  }

  Future<void> _resendConfirmationEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Enter your email above first, then try resending.');
      return;
    }
    try {
      await supabase.auth.resend(type: OtpType.signup, email: email);
      _showMessage('Confirmation email resent to $email.');
    } on AuthException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Could not resend the email. Try again.', isError: true);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showMessage('Enter your email above first, then tap this again.');
      return;
    }
    try {
      await supabase.auth.resetPasswordForEmail(email);
      _showMessage('Password reset email sent to $email.');
    } on AuthException catch (e) {
      _showMessage(e.message, isError: true);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    try {
      // Requires the redirect URL to be registered in Supabase Dashboard
      // (Authentication > URL Configuration) and as a native URL scheme —
      // see README.md, "Google sign-in setup".
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.findora://login-callback',
      );
    } on AuthException catch (e) {
      _showMessage(e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/logo.png', height: 52, width: 52),
                    const SizedBox(width: 12),
                    Text(
                      'Findora',
                      style: GoogleFonts.manrope(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1565D8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text('Welcome back', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  'Sign in to keep track of lost and found items near you.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (value) => (value == null || !value.contains('@'))
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) => (value == null || value.length < 6)
                      ? 'At least 6 characters'
                      : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _handleForgotPassword,
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _isSubmitting ? null : _handleLogin,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _handleGoogleSignIn,
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text('Continue with Google'),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account?",
                      style: theme.textTheme.bodyMedium,
                    ),
                    TextButton(
                      onPressed: () => context.push('/signup'),
                      child: const Text('Sign up'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
