import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/router/router.dart';
import '../../core/widgets/havenkeep_logo.dart';

/// Two-page first-launch intro that pitches the app's value before the
/// user hits the welcome / sign-in screen. Shown only on the very first
/// cold-start after install — gated by [introSeenPrefsKey] in
/// SharedPreferences. Returning users skip straight to /welcome.
class OnboardingIntroScreen extends StatefulWidget {
  const OnboardingIntroScreen({super.key});

  /// SharedPreferences key. Splash reads it to decide whether to route
  /// here or straight to /welcome on first launch.
  static const String introSeenPrefsKey = 'onboarding_intro_seen';

  @override
  State<OnboardingIntroScreen> createState() => _OnboardingIntroScreenState();
}

class _OnboardingIntroScreenState extends State<OnboardingIntroScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Two pages — kept short on purpose. Apple/Google design guidance both
  // recommend ≤3 intro screens before the first interactive surface.
  static const List<_IntroPage> _pages = [
    _IntroPage(
      gradient: [HavenColors.primary, HavenColors.secondary],
      icon: Icons.mark_email_read_outlined,
      title: 'Receipts arrive in your inbox.\nYour warranties live here.',
      body:
          'Connect Gmail or Outlook and HavenKeep auto-imports every '
          'purchase receipt. No data entry — just a complete library of '
          'everything you own and what it cost.',
    ),
    _IntroPage(
      gradient: [HavenColors.secondary, HavenColors.accent],
      icon: Icons.shield_outlined,
      title: 'Required maintenance keeps\nyour warranties valid.',
      body:
          'Skip a service interval, void the coverage. We schedule the '
          'right tasks per item, send reminders before they\'re due, and '
          'log every claim so you see exactly how much HavenKeep saved you.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _markSeenAndContinue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(OnboardingIntroScreen.introSeenPrefsKey, true);
    } catch (_) {
      // Best-effort; if prefs fails the splash will route here once more
      // on next cold-start. Not worth blocking navigation.
    }
    if (!mounted) return;
    context.go(AppRoutes.welcome);
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _markSeenAndContinue();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: HavenColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar — small wordmark + Skip on non-final pages.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HavenSpacing.lg,
                HavenSpacing.md,
                HavenSpacing.lg,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const HavenKeepLogo(size: 28, showWordmark: true),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isLastPage ? 0 : 1,
                    child: TextButton(
                      onPressed: isLastPage ? null : _markSeenAndContinue,
                      style: TextButton.styleFrom(
                        foregroundColor: HavenColors.textSecondary,
                      ),
                      child: const Text('Skip'),
                    ),
                  ),
                ],
              ),
            ),

            // PageView — the meat.
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _IntroPageView(page: _pages[i]),
              ),
            ),

            // Indicator + CTA.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HavenSpacing.lg,
                HavenSpacing.md,
                HavenSpacing.lg,
                HavenSpacing.xl,
              ),
              child: Column(
                children: [
                  _PageIndicator(
                    pageCount: _pages.length,
                    currentPage: _currentPage,
                  ),
                  const SizedBox(height: HavenSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HavenColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(HavenRadius.card),
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          isLastPage ? 'Get started' : 'Next',
                          key: ValueKey(isLastPage),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroPage {
  final List<Color> gradient;
  final IconData icon;
  final String title;
  final String body;

  const _IntroPage({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _IntroPageView extends StatelessWidget {
  final _IntroPage page;
  const _IntroPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero — gradient circle with the icon. Premium look without
          // requiring a custom illustration per page.
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: page.gradient,
                ),
                boxShadow: [
                  BoxShadow(
                    color: page.gradient.first.withValues(alpha: 0.35),
                    blurRadius: 60,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(page.icon, size: 96, color: Colors.white),
            ),
          ),
          const SizedBox(height: HavenSpacing.xxl),
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: HavenColors.textPrimary,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: HavenSpacing.md),
          Text(
            page.body,
            style: const TextStyle(
              fontSize: 16,
              color: HavenColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final int pageCount;
  final int currentPage;

  const _PageIndicator({
    required this.pageCount,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < pageCount; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            width: i == currentPage ? 28 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == currentPage
                  ? HavenColors.primary
                  : HavenColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          if (i != pageCount - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}
