import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/premium_provider.dart';
import '../../core/router/router.dart';

/// Contextual upsell card shown to non-premium users on the dashboard.
/// Prevents the paywall from being discoverable *only* after hitting the
/// 5-warranty limit, which turns the first premium encounter into frustration.
class PremiumTeaserCard extends ConsumerWidget {
  const PremiumTeaserCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);
    if (isPremium) return const SizedBox.shrink();

    return InkWell(
      borderRadius: BorderRadius.circular(HavenRadius.card),
      onTap: () => context.push(AppRoutes.premium),
      child: Container(
        padding: const EdgeInsets.all(HavenSpacing.lg),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [HavenColors.primary, HavenColors.secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(HavenRadius.card),
          boxShadow: [
            BoxShadow(
              color: HavenColors.primary.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(HavenSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(HavenRadius.button),
              ),
              child: const Icon(Icons.workspace_premium,
                  color: HavenColors.gold, size: 24),
            ),
            const SizedBox(width: HavenSpacing.md),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unlock Unlimited Warranties',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Receipt OCR, PDF export, priority support',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }
}
