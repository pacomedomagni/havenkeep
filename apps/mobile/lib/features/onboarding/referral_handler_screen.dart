import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

/// Handles deep link referral codes (e.g., havenkeep.app/r/JANE-SMITH).
///
/// Stores the referral code, then redirects to the welcome/dashboard.
class ReferralHandlerScreen extends ConsumerWidget {
  final String code;

  const ReferralHandlerScreen({super.key, required this.code});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: Store referral code for attribution during sign-up
    // Then redirect to welcome or dashboard
    return Scaffold(
      backgroundColor: HavenColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.link,
              size: 48,
              color: HavenColors.primary,
            ),
            const SizedBox(height: HavenSpacing.md),
            Text(
              'Referral: $code',
              style: const TextStyle(
                fontSize: 18,
                color: HavenColors.textPrimary,
              ),
            ),
            const SizedBox(height: HavenSpacing.sm),
            const Text(
              'Processing referral...',
              style: TextStyle(color: HavenColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
