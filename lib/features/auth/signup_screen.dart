import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/location/countries.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/widgets/password_strength.dart';
import '../items/widgets/country_field.dart';

/// Account creation. `signUp()` passes `full_name` and `country_code` in `data`, which the
/// `handle_new_user` trigger (see supabase/02_functions_and_triggers.sql)
/// reads when it creates the matching `profiles` row.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  /// Where this person lives — their posts are shown from here and Browse is
  /// filtered to it. Pre-filled from the phone's region; compulsory.
  String? _countryCode = _deviceCountry();

  static String? _deviceCountry() {
    final code = PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
    return isKnownCountry(code) ? code : null;
  }
  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Repaints the strength meter/checklist on every keystroke — a plain
    // ChangeNotifier-backed controller doesn't otherwise trigger a rebuild
    // of anything reading its `.text` outside the field itself.
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() => setState(() {});

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
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

  /// Asks the database whether this email is currently unavailable —
  /// recently deleted accounts have a cooldown, and moderation can block an
  /// address outright (supabase/16_release_email_on_delete.sql). Returns the
  /// message to show, or null if sign-up can go ahead.
  ///
  /// Fails open: if the check itself can't be made (offline, or the
  /// migration isn't applied yet) sign-up just proceeds, and the database
  /// trigger remains the real enforcement.
  Future<String?> _emailBlockedMessage(String email) async {
    try {
      final rows = await supabase.rpc('signup_email_status', params: {'p_email': email});
      final list = rows as List<dynamic>;
      if (list.isEmpty) return null;
      final retryAt = (list.first as Map<String, dynamic>)['retry_at'] as String?;
      if (retryAt == null) return "This email can't be used to create an account.";
      final date = DateFormat.yMMMd().format(DateTime.parse(retryAt).toLocal());
      return 'An account with this email was recently deleted. '
          'You can sign up with it again on $date.';
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final blockedMessage = await _emailBlockedMessage(_emailController.text.trim());
      if (blockedMessage != null) {
        _showMessage(blockedMessage, isError: true);
        return;
      }

      // Only passed when configured (see .env.example's AUTH_CALLBACK_URL)
      // — without it, Supabase falls back to its project-level Site URL,
      // which still works, just without web/auth-callback.html's "open the
      // app on mobile / auto-close the tab on desktop" behavior.
      final callbackUrl = dotenv.env['AUTH_CALLBACK_URL'];
      final response = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        // `country_code` is read by the handle_new_user trigger
        // (supabase/27_country_settings.sql) and saved on the new profile.
        data: {
          'full_name': _nameController.text.trim(),
          'country_code': _countryCode,
        },
        emailRedirectTo: (callbackUrl != null && callbackUrl.isNotEmpty) ? callbackUrl : null,
      );

      if (!mounted) return;

      if (response.session == null) {
        // Email confirmation is turned on for this project, so there's no
        // session yet — just a pending signup waiting on a confirmed email.
        _showMessage('Check your email to confirm your account, then sign in.');
        context.go('/login');
      }
      // If a session did come back (confirmation disabled), the router's
      // redirect callback takes care of navigating to /feed on its own.
    } on AuthException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage(
        'Something went wrong. Check your connection and try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Create your account', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  "It only takes a minute, and it's how we'll connect you "
                  'with someone who finds your things.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                CountryField(
                  value: _countryCode,
                  label: 'Country',
                  helper: 'Where you live — you will see posts from here',
                  onChanged: (code) => setState(() => _countryCode = code),
                ),
                const SizedBox(height: 16),
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
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: validateStrongPassword,
                ),
                const SizedBox(height: 12),
                PasswordStrengthIndicator(password: _passwordController.text),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) => value != _passwordController.text
                      ? "Passwords don't match"
                      : null,
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _isSubmitting ? null : _handleSignup,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create account'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
