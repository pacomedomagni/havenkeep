import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';

/// Add item screen -- method selection (fullscreenDialog).
///
/// Offers Quick-Add category grid, manual entry, and future scan methods.
class AddItemScreen extends ConsumerWidget {
  const AddItemScreen({super.key});

  /// Quick-add categories for the 3x3 grid.
  static const _quickAddCategories = [
    (ItemCategory.refrigerator, 'Fridge'),
    (ItemCategory.washer, 'Washer'),
    (ItemCategory.dryer, 'Dryer'),
    (ItemCategory.dishwasher, 'Dishwasher'),
    (ItemCategory.microwave, 'Microwave'),
    (ItemCategory.oven_range, 'Oven'),
    (ItemCategory.hvac, 'HVAC'),
    (ItemCategory.water_heater, 'Water Heater'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAtLimit = ref.watch(isAtItemLimitProvider).value ?? false;
    final itemCount = ref.watch(activeItemCountProvider).value ?? 0;

    if (isAtLimit) {
      return Scaffold(
        backgroundColor: HavenColors.background,
        appBar: AppBar(
          title: const Text(
            'Add New Item',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(HavenSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 72,
                  color: HavenColors.expiring,
                ),
                const SizedBox(height: HavenSpacing.md),
                const Text(
                  'Item Limit Reached',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: HavenColors.textPrimary,
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
                Text(
                  'You\'ve used $itemCount/$kFreePlanItemLimit free items.\nArchive old items or upgrade to add more.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: HavenColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: HavenSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.archivedItems);
                    },
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Manage Archived Items'),
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: null, // Phase 3
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Upgrade to Premium'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HavenColors.textTertiary,
                      side: const BorderSide(color: HavenColors.border),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text(
          'Add New Item',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(HavenSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quick-Add section
              const SectionHeader(title: 'Quick Add'),
              const SizedBox(height: HavenSpacing.sm),

              // 3x3 category grid
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: HavenSpacing.sm,
                crossAxisSpacing: HavenSpacing.sm,
                childAspectRatio: 1.0,
                children: [
                  ..._quickAddCategories.map(
                    (entry) => _CategoryTile(
                      category: entry.$1,
                      label: entry.$2,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        context.push('/add-item/quick/${entry.$1.name}');
                      },
                    ),
                  ),
                  // "Other" tile
                  _CategoryTile(
                    category: ItemCategory.other,
                    label: 'Other',
                    customEmoji: '\u{00B7}\u{00B7}\u{00B7}',
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      context.push('/add-item/quick/${ItemCategory.other.name}');
                    },
                  ),
                ],
              ),

              const SizedBox(height: HavenSpacing.lg),

              // Divider with "or"
              Row(
                children: [
                  const Expanded(child: Divider(color: HavenColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: HavenSpacing.md),
                    child: Text(
                      'or',
                      style: TextStyle(
                        fontSize: 13,
                        color: HavenColors.textTertiary,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: HavenColors.border)),
                ],
              ),

              const SizedBox(height: HavenSpacing.lg),

              // Method cards
              // 1. Scan Receipt (disabled)
              _MethodCard(
                icon: Icons.camera_alt_outlined,
                title: 'Scan Receipt',
                subtitle: 'Auto-extract details',
                isDisabled: true,
                disabledLabel: 'Coming soon',
                onTap: null,
              ),
              const SizedBox(height: HavenSpacing.sm),

              // 2. Full Manual Entry
              _MethodCard(
                icon: Icons.edit_outlined,
                title: 'Full Manual Entry',
                subtitle: 'All fields',
                isDisabled: false,
                onTap: () => context.push(AppRoutes.manualEntry),
              ),
              const SizedBox(height: HavenSpacing.sm),

              // 3. Scan Barcode (disabled)
              _MethodCard(
                icon: Icons.qr_code_scanner,
                title: 'Scan Barcode',
                subtitle: 'Look up product info',
                isDisabled: true,
                disabledLabel: 'Coming soon',
                onTap: null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable category tile for the quick-add grid.
class _CategoryTile extends StatelessWidget {
  final ItemCategory category;
  final String label;
  final String? customEmoji;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.label,
    this.customEmoji,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: HavenColors.elevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            customEmoji != null
                ? Text(
                    customEmoji!,
                    style: const TextStyle(fontSize: 28),
                  )
                : CategoryIcon.widget(category, size: 28),
            const SizedBox(height: HavenSpacing.sm),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: HavenColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// A method card for scan/manual entry options.
class _MethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDisabled;
  final String? disabledLabel;
  final VoidCallback? onTap;

  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isDisabled = false,
    this.disabledLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(HavenSpacing.md),
          decoration: BoxDecoration(
            color: HavenColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HavenColors.border),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: HavenColors.textSecondary,
                size: 24,
              ),
              const SizedBox(width: HavenSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: HavenColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: HavenColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isDisabled && disabledLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HavenSpacing.sm,
                    vertical: HavenSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: HavenColors.elevated,
                    borderRadius: BorderRadius.circular(HavenRadius.chip),
                  ),
                  child: Text(
                    disabledLabel!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: HavenColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else if (!isDisabled)
                const Icon(
                  Icons.chevron_right,
                  color: HavenColors.textTertiary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
