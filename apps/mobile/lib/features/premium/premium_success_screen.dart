import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/router/router.dart';

class PremiumSuccessScreen extends ConsumerWidget {
  const PremiumSuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(HavenSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 80,
                  color: HavenColors.active,
                ),
                const SizedBox(height: HavenSpacing.lg),
                const Text(
                  'Welcome to Premium!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: HavenColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: HavenSpacing.md),
                const Text(
                  'You now have unlimited items and all features unlocked.',
                  style: TextStyle(
                    fontSize: 16,
                    color: HavenColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: HavenSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.go(AppRoutes.dashboard),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HavenColors.primary,
                      foregroundColor: HavenColors.textPrimary,
                      padding: const EdgeInsets.symmetric(
                        vertical: HavenSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(HavenRadius.chip),
                      ),
                    ),
                    child: const Text(
                      'Start Using Premium',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
