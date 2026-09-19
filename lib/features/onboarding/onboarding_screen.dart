import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/onboarding/onboarding_prefs.dart';

class _OnboardingPage {
  const _OnboardingPage({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;
}

const _pages = [
  _OnboardingPage(
    icon: Icons.add_a_photo_outlined,
    title: 'Report what you lost or found',
    body: 'Snap a photo, add a location and a few details — it takes '
        'less than a minute to post a lost or found item.',
  ),
  _OnboardingPage(
    icon: Icons.auto_awesome_outlined,
    title: 'Let AI find your match',
    body: 'An on-device model compares your photo against everyone '
        "else's, right on your phone, and suggests likely matches "
        'automatically.',
  ),
  _OnboardingPage(
    icon: Icons.verified_user_outlined,
    title: 'Verify, then reunite safely',
    body: 'Confirm a match, chat about it, and approve a claim before '
        'any contact details are shared — then arrange a safe handoff.',
  ),
];

/// Shown once per device, before the first login — see
/// core/onboarding/onboarding_prefs.dart and the splash screen's redirect
/// logic, which is what actually decides whether this appears.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await OnboardingPrefs.markOnboardingSeen();
    if (!mounted) return;
    context.go('/login');
  }

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLastPage = _page == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: isLastPage ? null : _finish,
                  child: Text(
                    isLastPage ? '' : 'Skip',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primaryContainer,
                          ),
                          child: Icon(page.icon, size: 64, color: theme.colorScheme.primary),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: _next,
                child: Text(isLastPage ? 'Get started' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
