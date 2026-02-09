import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/router/router.dart';

/// Key for storing referral code in shared preferences.
const kReferralCodeKey = 'referral_code';

/// Handles deep link referral codes (e.g., havenkeep.app/r/JANE-SMITH).
///
/// Stores the referral code in local storage, then redirects to the welcome screen.
/// The auth flow reads this code during sign-up to attribute the referral.
class ReferralHandlerScreen extends ConsumerStatefulWidget {
  final String code;

  const ReferralHandlerScreen({super.key, required this.code});

  @override
  ConsumerState<ReferralHandlerScreen> createState() =>
      _ReferralHandlerScreenState();
}

class _ReferralHandlerScreenState
    extends ConsumerState<ReferralHandlerScreen> {
  @override
  void initState() {
    super.initState();
    _storeAndRedirect();
  }

  Future<void> _storeAndRedirect() async {
    try {
      // Store referral code for attribution during sign-up
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kReferralCodeKey, widget.code);
    } catch (_) {
      // Silently fail — referral is not critical
    }

    // Navigate to welcome screen
    if (mounted) {
      context.go(AppRoutes.welcome);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              'Referral: ${widget.code}',
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
            const SizedBox(height: HavenSpacing.lg),
            const CircularProgressIndicator(color: HavenColors.primary),
          ],
        ),
      ),
    );
  }
}
