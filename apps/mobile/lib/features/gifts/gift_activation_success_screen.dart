import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/utils/dates.dart';
import '../../core/widgets/havenkeep_logo.dart';

/// Gift-activation success surface. Dignified Cron-style celebration —
/// a gold-tinted [HavenSuccessFlourish] over a subtle brand gradient,
/// followed by the premium-feature recap and a single primary CTA.
/// No confetti, no marketing-heavy "Welcome to Premium!".
class GiftActivationSuccessScreen extends StatelessWidget {
  final int premiumMonths;

  const GiftActivationSuccessScreen({
    super.key,
    this.premiumMonths = 6,
  });

  @override
  Widget build(BuildContext context) {
    final expiryDate = addMonthsSafe(DateTime.now(), premiumMonths);
    final formattedDate =
        '${expiryDate.month}/${expiryDate.day}/${expiryDate.year}';

    return Scaffold(
      backgroundColor: HavenColors.canvas,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              HavenColors.primary.withValues(alpha: 0.10),
              HavenColors.canvas,
            ],
            stops: const [0.0, 0.5],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(HavenSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                const HavenSuccessFlourish(icon: Icons.auto_awesome_rounded),
                const SizedBox(height: HavenSpacing.lg),
                const Text(
                  'Premium activated',
                  style: HavenText.displayLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: HavenSpacing.sm),
                const Text(
                  'Your gift is live. Enjoy the full experience.',
                  style: HavenText.bodySecondary,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: HavenSpacing.xl),

                HavenCard.elevated(
                  glow: HavenColors.gold,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.workspace_premium_rounded,
                            color: HavenColors.gold,
                            size: 28,
                          ),
                          const SizedBox(width: HavenSpacing.sm),
                          Text(
                            '$premiumMonths months Premium',
                            style: HavenText.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: HavenSpacing.xs),
                      Text(
                        'Active until $formattedDate',
                        style: HavenText.meta,
                      ),
                      const SizedBox(height: HavenSpacing.md),
                      const Divider(color: HavenColors.borderHairline),
                      const SizedBox(height: HavenSpacing.md),
                      const _Feature(
                        icon: Icons.inventory_2_outlined,
                        text: 'Track unlimited items',
                      ),
                      const SizedBox(height: HavenSpacing.sm + 2),
                      const _Feature(
                        icon: Icons.receipt_long_rounded,
                        text: 'Store unlimited documents',
                      ),
                      const SizedBox(height: HavenSpacing.sm + 2),
                      const _Feature(
                        icon: Icons.notifications_active_outlined,
                        text: 'Smart warranty reminders',
                      ),
                      const SizedBox(height: HavenSpacing.sm + 2),
                      const _Feature(
                        icon: Icons.trending_up_rounded,
                        text: 'Advanced analytics',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: HavenSpacing.xl),
                HavenButton.primary(
                  label: 'Get started',
                  onPressed: () => context.go('/dashboard'),
                  expand: true,
                  size: HavenButtonSize.lg,
                ),
                const Spacer(),
                const HavenKeepLogo(size: 32),
                const SizedBox(height: HavenSpacing.xs),
                const Text(
                  'Thank you for choosing HavenKeep',
                  style: HavenText.caption,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Feature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: HavenColors.primary, size: 20),
        const SizedBox(width: HavenSpacing.sm + 4),
        Expanded(child: Text(text, style: HavenText.body)),
      ],
    );
  }
}
