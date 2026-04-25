import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';

/// Success screen shown after an item is added.
///
/// Displays a confirmation with item details and navigation options.
class ItemAddedScreen extends ConsumerStatefulWidget {
  final String itemId;

  /// The just-created item, if available. When provided, the screen renders
  /// immediately from this snapshot and skips the detail-provider round
  /// trip that would otherwise show a "couldn't load" fallback while sync
  /// catches up (Ch05-F020).
  final Item? initialItem;

  const ItemAddedScreen({
    super.key,
    required this.itemId,
    this.initialItem,
  });

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
    // Ch05-F020: when caller pre-seeded an Item, skip the provider entirely
    // — it can lag behind sync replay and would otherwise flash an error
    // fallback right after a successful save.
    final preseeded = widget.initialItem;
    if (preseeded != null) {
      return Scaffold(
        backgroundColor: HavenColors.background,
        body: SafeArea(child: _buildSuccess(preseeded)),
      );
    }

    final itemAsync = ref.watch(itemDetailProvider(widget.itemId));

    return Scaffold(
      backgroundColor: HavenColors.background,
      body: SafeArea(
        child: itemAsync.when(
          data: _buildSuccess,
          loading: () => const Padding(
            padding: EdgeInsets.all(HavenSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
                    "Item was saved but details couldn't load. View it from your items list.",
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

  /// Renders the celebration body for a fully-loaded item.
  Widget _buildSuccess(Item item) {
    final displayName = '${item.brand ?? ''} ${item.name}'.trim();

    // warranty_end_date is a generated NOT NULL column on the API
    // (Ch08-Item-D010); the model exposes it as non-null after Phase 8.
    final expiryText =
        'Warranty expires ${DateFormat('MMM d, yyyy').format(item.warrantyEndDate)}';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HavenSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: const Icon(
                Icons.check_circle,
                size: 80,
                color: HavenColors.active,
              ),
            ),
            const SizedBox(height: HavenSpacing.lg),
            const Text(
              'Item Added!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: HavenColors.primary,
              ),
            ),
            const SizedBox(height: HavenSpacing.sm),
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
            Text(
              expiryText,
              style: const TextStyle(
                fontSize: 14,
                color: HavenColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HavenSpacing.xs),
            const Text(
              "We'll remind you before it expires.",
              style: TextStyle(
                fontSize: 13,
                color: HavenColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HavenSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go('/items/${widget.itemId}'),
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
  }
}
