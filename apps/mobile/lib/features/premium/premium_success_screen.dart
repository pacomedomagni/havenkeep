import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/router/router.dart';

/// Premium upgrade success surface. Same dignified flourish as gift
/// activation — gold sweep, no confetti, one primary CTA.
class PremiumSuccessScreen extends ConsumerWidget {
  const PremiumSuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(HavenSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HavenSuccessFlourish(
                    icon: Icons.workspace_premium_rounded,
                  ),
                  const SizedBox(height: HavenSpacing.lg),
                  const Text(
                    'Premium unlocked',
                    style: HavenText.displayLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: HavenSpacing.sm),
                  const Text(
                    'Unlimited items, smart reminders, and every advanced '
                    'feature, now active on your account.',
                    style: HavenText.bodySecondary,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: HavenSpacing.xxl),
                  HavenButton.primary(
                    label: 'Start using Premium',
                    onPressed: () => context.go(AppRoutes.dashboard),
                    expand: true,
                    size: HavenButtonSize.lg,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
