import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

/// Preview/onboarding screens shown before authentication.
/// Shows value proposition with beautiful animations.
class PreviewScreen extends StatefulWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onTryDemo;

  const PreviewScreen({
    super.key,
    required this.onGetStarted,
    required this.onTryDemo,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button (Ch05-F082: name the action so VoiceOver
            // reads "Skip onboarding, button" instead of just "Skip").
            Align(
              alignment: Alignment.topRight,
              child: Semantics(
                button: true,
                label: 'Skip onboarding and continue',
                child: ConstrainedBox(
                  // Ch05-F084: 48dp minimum tap target.
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  child: TextButton(
                    onPressed: widget.onGetStarted,
                    child: const Text('Skip'),
                  ),
                ),
              ),
            ),

            // Page view
            Expanded(
              child: PageView(
                controller: _pageController,
                children: const [
                  _PreviewPage(
                    icon: Icons.shield_outlined,
                    title: 'Your warranties,\nprotected',
                    subtitle:
                        'Track all your warranties in one place. Never lose another receipt.',
                    color: HavenColors.accent,
                  ),
                  _PreviewPage(
                    icon: Icons.qr_code_scanner,
                    title: 'Add items\nin seconds',
                    subtitle:
                        'Scan barcodes or snap receipts. Simple 3-step wizard.',
                    color: HavenColors.active,
                  ),
                  _PreviewPage(
                    icon: Icons.notifications_outlined,
                    title: 'Never miss\nan expiration',
                    subtitle:
                        'Get notified before warranties expire. Claim what you deserve.',
                    color: HavenColors.expiring,
                  ),
                ],
              ),
            ),

            // Page indicator
            SmoothPageIndicator(
              controller: _pageController,
              count: 3,
              effect: WormEffect(
                dotHeight: 8,
                dotWidth: 8,
                activeDotColor: Theme.of(context).primaryColor,
                dotColor: HavenColors.textTertiary,
              ),
            ),

            const SizedBox(height: 32),

            // CTAs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Primary CTA
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: widget.onGetStarted,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(HavenRadius.card),
                        ),
                      ),
                      child: const Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Demo CTA
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: widget.onTryDemo,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(HavenRadius.card),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_circle_outline,
                              color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          const Text(
                            'Try Interactive Demo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _PreviewPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _PreviewPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Simple icon (no Lottie needed - fast & clean). Marked
          // decorative-only (Ch05-F082) so screen readers read the
          // headline below it rather than guessing at the icon glyph.
          ExcludeSemantics(
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 80,
                color: color,
              ),
            ),
          ),

          const SizedBox(height: 48),

          // Title (Ch05-F085: textPrimary on dark background hits
          // WCAG AA 4.5:1; we keep the strict colour and don't tint
          // it to match the icon.)
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: HavenColors.textPrimary,
                height: 1.2,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Subtitle
          Text(
            subtitle,
            textAlign: TextAlign.center,
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
