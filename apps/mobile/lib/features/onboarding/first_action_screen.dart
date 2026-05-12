import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/router/router.dart';
import '../../core/utils/haven_haptics.dart';

/// First Action screen (Screen 1.3) — "What do you want to do first?"
///
/// Shown after sign-up for new users who don't have a home yet.
/// Offers: Set up home (bulk-add), add item manually, or explore.
class FirstActionScreen extends ConsumerWidget {
  const FirstActionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final firstName = user.value?.fullName.split(' ').first ?? 'there';

    return Scaffold(
      backgroundColor: HavenColors.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(HavenSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: HavenSpacing.xxl),

              // Greeting
              Text('Welcome, $firstName', style: HavenText.displayLarge),
              const SizedBox(height: HavenSpacing.sm),
              Text(
                'What would you like to do first?',
                style: HavenText.bodySecondary.copyWith(fontSize: 16),
              ),

              const SizedBox(height: HavenSpacing.xl),

              // Option 1: Set up home (bulk-add)
              _ActionCard(
                icon: Icons.home_outlined,
                title: 'Set up my new home',
                description:
                    'Walk through each room and add your appliances in minutes.',
                onTap: () => context.go(AppRoutes.homeSetup),
              ),
              const SizedBox(height: HavenSpacing.md),

              // Option 2: Scan receipt
              _ActionCard(
                icon: Icons.photo_camera_outlined,
                title: 'Scan a receipt',
                description:
                    "Snap a photo and we'll extract the details automatically.",
                onTap: () => context.push(AppRoutes.scanReceipt),
              ),
              const SizedBox(height: HavenSpacing.md),

              // Option 3: Add item manually
              _ActionCard(
                icon: Icons.edit_outlined,
                title: 'Add an item manually',
                description: 'Enter all the details yourself.',
                onTap: () => context.push(AppRoutes.addItem),
              ),

              const SizedBox(height: HavenSpacing.xl),

              // Skip link
              Center(
                child: TextButton(
                  onPressed: () => context.go(AppRoutes.dashboard),
                  style: TextButton.styleFrom(
                    foregroundColor: HavenColors.textSecondary,
                  ),
                  child: const Text("I'll explore first"),
                ),
              ),

              const SizedBox(height: HavenSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable option card for the first action screen.
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HavenCard.elevated(
      padding: const EdgeInsets.all(HavenSpacing.lg),
      semanticLabel: '$title. $description',
      onTap: () {
        HavenHaptics.confirm();
        onTap();
      },
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(HavenSpacing.sm + 2),
            decoration: BoxDecoration(
              color: HavenColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(HavenRadius.button),
              border: Border.all(
                color: HavenColors.primary.withValues(alpha: 0.16),
              ),
            ),
            child: Icon(icon, size: 24, color: HavenColors.primary),
          ),
          const SizedBox(width: HavenSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: HavenText.titleLarge),
                const SizedBox(height: HavenSpacing.xs),
                Text(description, style: HavenText.meta),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: HavenColors.textTertiary),
        ],
      ),
    );
  }
}
