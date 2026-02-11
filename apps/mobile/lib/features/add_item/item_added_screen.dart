import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';

/// Success screen shown after an item is added.
///
/// Displays a confirmation with item details and navigation options.
class ItemAddedScreen extends ConsumerStatefulWidget {
  final String itemId;

  const ItemAddedScreen({super.key, required this.itemId});

  @override
  ConsumerState<ItemAddedScreen> createState() => _ItemAddedScreenState();
}

class _ItemAddedScreenState extends ConsumerState<ItemAddedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
    _scaleController.forward();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemAsync = ref.watch(itemDetailProvider(widget.itemId));

    return Scaffold(
      backgroundColor: HavenColors.background,
      body: SafeArea(
        child: itemAsync.when(
          data: (item) {
            final displayName =
                '${item.brand ?? ''} ${item.name}'.trim();

            String? expiryText;
            if (item.warrantyEndDate != null) {
              expiryText =
                  'Warranty expires ${DateFormat('MMM d, yyyy').format(item.warrantyEndDate!)}';
            } else {
              final computed = DateTime(item.purchaseDate.year, item.purchaseDate.month + item.warrantyMonths, item.purchaseDate.day);
              expiryText =
                  'Warranty expires ${DateFormat('MMM d, yyyy').format(computed)}';
            }

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(HavenSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated check icon
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: const Icon(
                        Icons.check_circle,
                        size: 80,
                        color: HavenColors.active,
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.lg),

                    // Title
                    const Text(
                      'Item Added!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: HavenColors.primary,
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.sm),

                    // Item name
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: HavenColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: HavenSpacing.sm),

                    // Expiry text
                    Text(
                      expiryText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: HavenColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: HavenSpacing.xs),

                    // Reminder text
                    const Text(
                      "We'll remind you before it expires.",
                      style: TextStyle(
                        fontSize: 13,
                        color: HavenColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: HavenSpacing.xxl),

                    // Action buttons
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            context.go('/items/${widget.itemId}'),
                        child: const Text(
                          'View Item',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.sm),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => context.go(AppRoutes.addItem),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: HavenColors.textPrimary,
                          side: const BorderSide(color: HavenColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(HavenRadius.button),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: HavenSpacing.lg,
                            vertical: HavenSpacing.md,
                          ),
                        ),
                        child: const Text(
                          'Add Another',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.sm),

                    TextButton(
                      onPressed: () => context.go(AppRoutes.dashboard),
                      child: const Text(
                        'Go to Dashboard',
                        style: TextStyle(
                          fontSize: 15,
                          color: HavenColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.all(HavenSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SkeletonBox(width: 80, height: 80),
                SizedBox(height: HavenSpacing.lg),
                SkeletonLine(width: 200, height: 24),
                SizedBox(height: HavenSpacing.md),
                SkeletonLine(width: 280, height: 16),
              ],
            ),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(HavenSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 80,
                    color: HavenColors.expiring,
                  ),
                  const SizedBox(height: HavenSpacing.lg),
                  const Text(
                    'Item Saved',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.sm),
                  const Text(
                    'Item was saved but details could not be loaded.',
                    style: TextStyle(
                      fontSize: 14,
                      color: HavenColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: HavenSpacing.xxl),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => context.go(AppRoutes.dashboard),
                      child: const Text('Go to Dashboard'),
                    ),
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
