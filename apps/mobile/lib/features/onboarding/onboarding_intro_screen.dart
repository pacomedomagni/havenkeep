import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/router/router.dart';
import '../../core/widgets/havenkeep_logo.dart';

/// Three-page, photo-backed first-launch intro. Shown only on the very
/// first cold-start after install — gated by [introSeenPrefsKey] in
/// SharedPreferences; returning users skip straight to /welcome.
///
/// Each page is a full-bleed photograph (bundled, ~590 KB total — see
/// assets/images/onboarding/CREDITS.md) under a dark gradient scrim and a
/// faint indigo wash, with a small icon chip + headline + body anchored to
/// the bottom over the darkest part. The photo crossfades + does a slow
/// Ken-Burns drift between pages. If a photo asset is ever missing the
/// page falls back to a brand-gradient fill, so onboarding never breaks.
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

  // Three pages — own it / inbox→warranties / stay covered. Apple & Google
  // both recommend ≤3 intro screens before the first interactive surface.
  static const List<_IntroPage> _pages = [
    _IntroPage(
      asset: 'assets/images/onboarding/1.jpg',
      fallbackGradient: [HavenColors.primary, HavenColors.secondary],
      icon: Icons.home_outlined,
      title: 'Everything you own,\nin one place.',
      body:
          'Your fridge, your TV, the new roof — HavenKeep keeps a complete '
          'record of what you own, what it cost, and how long it\'s covered.',
    ),
    _IntroPage(
      asset: 'assets/images/onboarding/2.jpg',
      fallbackGradient: [HavenColors.secondary, HavenColors.accent],
      icon: Icons.mark_email_read_outlined,
      title: 'Receipts in your inbox\nbecome warranties here.',
      body:
          'Connect Gmail or Outlook and HavenKeep imports every purchase '
          'receipt automatically. No data entry — your library builds itself.',
    ),
    _IntroPage(
      asset: 'assets/images/onboarding/3.jpg',
      fallbackGradient: [HavenColors.accent, HavenColors.accentSecondary],
      icon: Icons.verified_outlined,
      title: 'Stay covered.\nNever miss a beat.',
      body:
          'We schedule the maintenance that keeps coverage valid, remind you '
          'before anything\'s due, and log every claim — so your home is handled.',
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
        duration: HavenMotion.slow,
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
      backgroundColor: HavenColors.canvas,
      body: Stack(
        children: [
          // ── The photo layer — crossfades between pages ───────────────
          // We paint the *current* page's photo full-bleed under everything.
          // PageView (transparent) rides on top for the swipe gesture +
          // the text content; AnimatedSwitcher dissolves the photo when
          // _currentPage changes so the swipe slides the text but the
          // background fades — feels more cinematic than a hard slide.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _PhotoBackdrop(
                key: ValueKey(_currentPage),
                page: _pages[_currentPage],
              ),
            ),
          ),

          // ── Foreground: top bar + swipeable text + indicator + CTA ───
          SafeArea(
            child: Column(
              children: [
                // Top bar — small wordmark + Skip on non-final pages.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      HavenSpacing.lg, HavenSpacing.md, HavenSpacing.lg, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const HavenKeepLogo(size: 26, showWordmark: true),
                      AnimatedOpacity(
                        duration: HavenMotion.fast,
                        opacity: isLastPage ? 0 : 1,
                        child: TextButton(
                          onPressed: isLastPage ? null : _markSeenAndContinue,
                          style: TextButton.styleFrom(
                            foregroundColor:
                                Colors.white.withValues(alpha: 0.85),
                          ),
                          child: const Text('Skip'),
                        ),
                      ),
                    ],
                  ),
                ),

                // Swipeable text content. The PageView itself is
                // transparent — only the headline/body live here; the
                // photo is the AnimatedSwitcher layer behind.
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemCount: _pages.length,
                    itemBuilder: (_, i) => _IntroPageText(page: _pages[i]),
                  ),
                ),

                // Indicator + CTA over the darkest part of the scrim.
                Padding(
                  padding: const EdgeInsets.fromLTRB(HavenSpacing.lg,
                      HavenSpacing.md, HavenSpacing.lg, HavenSpacing.xl),
                  child: Column(
                    children: [
                      _PageIndicator(
                        pageCount: _pages.length,
                        currentPage: _currentPage,
                      ),
                      const SizedBox(height: HavenSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(HavenRadius.card),
                            boxShadow:
                                HavenElevation.glow(HavenColors.primary),
                          ),
                          child: FilledButton(
                            onPressed: _nextPage,
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(HavenRadius.card),
                              ),
                            ),
                            child: AnimatedSwitcher(
                              duration: HavenMotion.fast,
                              child: Text(
                                isLastPage ? 'Get started' : 'Continue',
                                key: ValueKey(isLastPage),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
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
        ],
      ),
    );
  }
}

class _IntroPage {
  final String asset;
  final List<Color> fallbackGradient;
  final IconData icon;
  final String title;
  final String body;

  const _IntroPage({
    required this.asset,
    required this.fallbackGradient,
    required this.icon,
    required this.title,
    required this.body,
  });
}

/// Full-bleed photo (or gradient fallback) + a slow Ken-Burns drift + the
/// dark scrim that makes the bottom-anchored text legible + a faint indigo
/// brand wash.
class _PhotoBackdrop extends StatefulWidget {
  final _IntroPage page;
  const _PhotoBackdrop({super.key, required this.page});

  @override
  State<_PhotoBackdrop> createState() => _PhotoBackdropState();
}

class _PhotoBackdropState extends State<_PhotoBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ken;

  @override
  void initState() {
    super.initState();
    // Slow zoom + pan over ~14s, ping-ponging so it never snaps.
    _ken = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The photo, gently scaled + nudged.
        AnimatedBuilder(
          animation: _ken,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_ken.value);
            return Transform.scale(
              scale: 1.06 + 0.06 * t, // 1.06 → 1.12
              alignment: Alignment.lerp(
                Alignment.topCenter,
                Alignment.bottomCenter,
                t,
              )!,
              child: child,
            );
          },
          child: Image.asset(
            widget.page.asset,
            fit: BoxFit.cover,
            // If the asset is ever missing (e.g. a fresh checkout before
            // the photos are committed), fall back to the brand gradient
            // so the page still renders.
            errorBuilder: (_, __, ___) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.page.fallbackGradient,
                ),
              ),
            ),
          ),
        ),

        // Dark gradient scrim — transparent up top (photo breathes),
        // ramping to near-black at the bottom where the headline + CTA sit.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                HavenColors.canvas.withValues(alpha: 0.20),
                HavenColors.canvas.withValues(alpha: 0.10),
                HavenColors.canvas.withValues(alpha: 0.55),
                HavenColors.canvas.withValues(alpha: 0.94),
              ],
              stops: const [0.0, 0.32, 0.62, 1.0],
            ),
          ),
        ),

        // A faint indigo brand wash so the photos read as "ours".
        DecoratedBox(
          decoration: BoxDecoration(
            color: HavenColors.primary.withValues(alpha: 0.06),
          ),
        ),
      ],
    );
  }
}

/// The text content of one intro page — icon chip + headline + body,
/// anchored to the bottom over the scrim. (The photo lives in
/// [_PhotoBackdrop], rendered behind the whole PageView.)
class _IntroPageText extends StatelessWidget {
  final _IntroPage page;
  const _IntroPageText({required this.page});

  static const _textShadow = [
    Shadow(color: Color(0xCC000000), blurRadius: 16, offset: Offset(0, 2)),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Small frosted icon chip.
          Container(
            padding: const EdgeInsets.all(HavenSpacing.sm + 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(HavenRadius.button),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(page.icon, size: 22, color: Colors.white),
          ),
          const SizedBox(height: HavenSpacing.md + 2),
          Text(
            page.title,
            style: HavenText.hero.copyWith(
              fontSize: 30,
              height: 1.15,
              color: Colors.white,
              shadows: _textShadow,
            ),
          ),
          const SizedBox(height: HavenSpacing.sm + 2),
          Text(
            page.body,
            style: HavenText.body.copyWith(
              fontSize: 15,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.9),
              shadows: _textShadow,
            ),
          ),
          const SizedBox(height: HavenSpacing.lg),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final int pageCount;
  final int currentPage;

  const _PageIndicator({required this.pageCount, required this.currentPage});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < pageCount; i++) ...[
          AnimatedContainer(
            duration: HavenMotion.medium,
            curve: Curves.easeOutCubic,
            width: i == currentPage ? 26 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == currentPage
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          if (i != pageCount - 1) const SizedBox(width: 7),
        ],
      ],
    );
  }
}
