import 'dart:async';
import 'dart:math' as math; // Added back for the spinner math

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/onboarding/onboarding_prefs.dart';
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

// Changed to TickerProviderStateMixin because we now have TWO animation controllers
class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _spinController;
  late final Animation<double> _logoScale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    
    // Entrance Animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoScale = CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0, 0.6, curve: Curves.easeOut),
    );
    _entranceController.forward();

    // Spinner Animation
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    // Long enough for the entrance animation and loading ring to actually
    // read as "loading" rather than flashing past — short enough not to
    // feel like an artificial delay.
    Timer(const Duration(milliseconds: 5000), _redirect);
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _redirect() async {
    final session = supabase.auth.currentSession;
    if (session != null) {
      if (mounted) context.go('/feed');
      return;
    }

    final hasSeenOnboarding = await OnboardingPrefs.hasSeenOnboarding();
    if (!mounted) return;
    context.go(hasSeenOnboarding ? '/login' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = theme.colorScheme.onPrimary;

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      body: Stack(
        children: [
          const ExcludeSemantics(child: _BackgroundDecoration()),
          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SizedBox(
                width: double.infinity, 
                child: Column(
                  children: [
                    const Spacer(flex: 4),
                    ScaleTransition(
                      scale: _logoScale,
                      child: const _LogoBadge(),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Findora',
                      style: GoogleFonts.manrope(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: onPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The Smart Lost & Found',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: onPrimary.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(flex: 4),
                    
                    // Replaced LinearProgressIndicator with the animated spin ring
                    AnimatedBuilder(
                      animation: _spinController,
                      builder: (context, child) => Transform.rotate(
                        angle: _spinController.value * 2 * math.pi,
                        child: child,
                      ),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        // Passing `onPrimary` so the ring matches the new theme
                        child: CustomPaint(painter: _FadingRingPainter(color: onPrimary)),
                      ),
                    ),
                    
                    const SizedBox(height: 18),
                    Text(
                      'Initializing AI Engine...',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: onPrimary,
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The logo on a white circular badge, so it reads with full contrast
/// regardless of exactly which shade `colorScheme.primary` resolves to.
class _LogoBadge extends StatelessWidget {
  const _LogoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      height: 168,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
    );
  }
}

/// A handful of soft, translucent circles for visual depth.
class _BackgroundDecoration extends StatelessWidget {
  const _BackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    final tint = Colors.white.withValues(alpha: 0.08);
    return Stack(
      children: [
        Positioned(top: -60, left: -40, child: _circle(180, tint)),
        Positioned(top: 120, right: -70, child: _circle(220, tint)),
        Positioned(bottom: -80, left: -60, child: _circle(240, tint)),
      ],
    );
  }

  Widget _circle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// A ring of short dashes with fading opacity around the circle, rotated
/// continuously — reads as "AI is working" rather than a generic spinner.
class _FadingRingPainter extends CustomPainter {
  const _FadingRingPainter({required this.color});

  final Color color;
  static const _dashCount = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final paint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < _dashCount; i++) {
      final startAngle = (2 * math.pi / _dashCount) * i;
      const sweep = (2 * math.pi / _dashCount) * 0.55;
      final opacity = (i + 1) / _dashCount;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FadingRingPainter oldDelegate) => false;
}