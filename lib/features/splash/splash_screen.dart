import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    // Long enough for the loading ring to actually read as "loading"
    // rather than flashing past — short enough not to feel like a delay.
    Timer(const Duration(milliseconds: 1800), _redirect);
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _redirect() {
    if (!mounted) return;
    final session = supabase.auth.currentSession;
    context.go(session == null ? '/login' : '/feed');
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF1565D8);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFDCEEFC)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 4),
              Image.asset(
                'assets/images/logo.png',
                width: 176,
                height: 176,
              ),
              const SizedBox(height: 20),
              Text(
                'Findora',
                style: GoogleFonts.manrope(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: brandBlue,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'AI-Powered Lost & Found',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: const Color(0xFF6B7B8C),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(flex: 4),
              AnimatedBuilder(
                animation: _spinController,
                builder: (context, child) => Transform.rotate(
                  angle: _spinController.value * 2 * math.pi,
                  child: child,
                ),
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: CustomPaint(painter: _FadingRingPainter(color: brandBlue)),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Initializing AI Engine...',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: brandBlue,
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
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
