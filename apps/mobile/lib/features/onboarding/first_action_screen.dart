import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/router/router.dart';

/// First Action screen (Screen 1.3) — "What do you want to do first?"
///
/// Shown after sign-up for new users who don't have a home yet.
/// Offers: Set up home (bulk-add), add item manually, or explore.
class FirstActionScreen extends ConsumerWidget {
  const FirstActionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final firstName = user.value?.fullName?.split(' ').first ?? 'there';

    return Scaffold(
      backgroundColor: HavenColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(HavenSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: HavenSpacing.xxl),

              // Greeting
              Text(
                'Welcome, $firstName!',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: HavenColors.textPrimary,
                ),
              ),
              const SizedBox(height: HavenSpacing.sm),
              const Text(
                'What would you like to do first?',
                style: TextStyle(
                  fontSize: 18,
                  color: HavenColors.textSecondary,
                ),
              ),

              const SizedBox(height: HavenSpacing.xl),

              // Option 1: Set up home (bulk-add)
              _ActionCard(
                icon: '🏠',
                title: 'Set up my new home',
                description:
                    'Walk through each room and add your appliances in minutes.',
                onTap: () => context.go(AppRoutes.homeSetup),
              ),

              const SizedBox(height: HavenSpacing.md),

              // Option 2: Scan receipt
              _ActionCard(
                icon: '📷',
                title: 'Scan a receipt',
                description:
                    'Snap a photo and we\'ll extract the details automatically.',
                onTap: () => context.push(AppRoutes.scanReceipt),
              ),

              const SizedBox(height: HavenSpacing.md),

              // Option 3: Add item manually
              _ActionCard(
                icon: '✏️',
                title: 'Add an item manually',
                description: 'Enter all the details yourself.',
                onTap: () => context.push(AppRoutes.addItem),
              ),

              const SizedBox(height: HavenSpacing.xl),

              // Skip link
              Center(
                child: GestureDetector(
                  onTap: () => context.go(AppRoutes.dashboard),
                  child: const Text(
                    "I'll explore first →",
                    style: TextStyle(
                      fontSize: 16,
                      color: HavenColors.textSecondary,
                    ),
                  ),
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
  final String icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool isDisabled;
  final String? disabledLabel;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.isDisabled = false,
    this.disabledLabel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDisabled
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onTap();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(HavenSpacing.lg),
        decoration: BoxDecoration(
          color: HavenColors.elevated,
          borderRadius: BorderRadius.circular(HavenRadius.card),
          border: Border.all(
            color: isDisabled
                ? HavenColors.border
                : HavenColors.border,
          ),
        ),
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Row(
            children: [
              // Icon
              Text(
                icon,
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(width: HavenSpacing.md),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: HavenColors.textPrimary,
                          ),
                        ),
                        if (disabledLabel != null) ...[
                          const SizedBox(width: HavenSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: HavenSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: HavenColors.surface,
                              borderRadius:
                                  BorderRadius.circular(HavenRadius.chip),
                            ),
                            child: Text(
                              disabledLabel!,
                              style: const TextStyle(
                                fontSize: 10,
                                color: HavenColors.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: HavenSpacing.xs),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: HavenColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Chevron
              if (!isDisabled)
                const Icon(
                  Icons.chevron_right,
                  color: HavenColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
