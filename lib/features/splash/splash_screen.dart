import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase/supabase_client.dart';

/// Shown briefly on cold start while we decide whether the user already
/// has a Supabase session. This makes the very first hop; every navigation
/// after that is gated by the router's own `redirect` callback, which also
/// reacts live if a session expires mid-use.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 800), _redirect);
  }

  void _redirect() {
    if (!mounted) return;
    final session = supabase.auth.currentSession;
    context.go(session == null ? '/login' : '/feed');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/images/pin_glyph_white.svg',
              width: 72,
              height: 72,
            ),
            const SizedBox(height: 16),
            Text(
              'Findora',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
