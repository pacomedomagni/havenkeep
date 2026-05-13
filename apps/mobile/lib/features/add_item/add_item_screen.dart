import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_client/api_client.dart';
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
    // Ch05-F001: never silently treat the limit as "false" on error/loading
    // — that lets a free user past the cap when the API hiccups. We use the
    // `.when` pattern so loading and error each get their own UI.
    final atLimitAsync = ref.watch(isAtItemLimitProvider);
    final itemCount = ref.watch(activeItemCountProvider).value ?? 0;

    return atLimitAsync.when(
      loading: () => const Scaffold(
        backgroundColor: HavenColors.background,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
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
                  Icons.cloud_off,
                  size: 64,
                  color: HavenColors.expired,
                ),
                const SizedBox(height: HavenSpacing.md),
                const Text(
                  "We couldn't check your plan",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: HavenColors.textPrimary,
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
                const Text(
                  "Try again in a moment so we don't accidentally let you past your free-plan cap.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: HavenColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: HavenSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () =>
                        ref.invalidate(isAtItemLimitProvider),
                    child: const Text('Try Again'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (isAtLimit) => _buildContent(
        context,
        isAtLimit: isAtLimit,
        itemCount: itemCount,
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required bool isAtLimit,
    required int itemCount,
  }) {
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
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.premium);
                    },
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Upgrade to Premium'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HavenColors.primary,
                      side: const BorderSide(color: HavenColors.primary),
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
              const SectionHeader(title: 'Add in seconds'),
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
                        // Ch05-F002: navigation triggers should use the
                        // light "tap" haptic; "confirm" is reserved for
                        // completed actions like a successful save.
                        HavenHaptics.tap();
                        context.push('/add-item/quick/${entry.$1.name}');
                      },
                    ),
                  ),
                  // "Other" tile
                  _CategoryTile(
                    category: ItemCategory.other,
                    label: 'Other',
                    onTap: () {
                      HavenHaptics.tap();
                      context.push('/add-item/quick/${ItemCategory.other.name}');
                    },
                  ),
                ],
              ),

              const SizedBox(height: HavenSpacing.lg),

              // Divider with "or"
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: HavenSpacing.md),
                    child: Text('or',
                        style: HavenText.caption.copyWith(letterSpacing: 1)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: HavenSpacing.lg),

              // Method cards
              // 1. Scan Receipt — AI-assisted
              _MethodCard(
                icon: Icons.camera_alt_outlined,
                title: 'Snap a receipt',
                subtitle: 'Our AI fills in the details',
                isDisabled: false,
                onTap: () => context.push(AppRoutes.scanReceipt),
              ),
              const SizedBox(height: HavenSpacing.sm),

              // 2. Barcode — product lookup
              _MethodCard(
                icon: Icons.qr_code_scanner,
                title: 'Scan a barcode',
                subtitle: 'Auto-identify your product',
                isDisabled: false,
                onTap: () => context.push(AppRoutes.scanBarcode),
              ),
              const SizedBox(height: HavenSpacing.sm),

              // 3. Manual entry — fallback for rarely-used items
              _MethodCard(
                icon: Icons.edit_outlined,
                title: 'Enter it yourself',
                subtitle: 'Type all the details',
                isDisabled: false,
                onTap: () => context.push(AppRoutes.manualEntry),
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
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Ch05 a11y: every quick-add tile is a button; expose the label so
    // VoiceOver/TalkBack reads "Add Fridge button" instead of "image".
    return HavenCard.elevated(
      padding: EdgeInsets.zero,
      semanticLabel: 'Add $label',
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CategoryIcon.widget(category, size: 24, boxed: false),
            const SizedBox(height: HavenSpacing.sm),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: HavenSpacing.xs),
              child: Text(
                label,
                style: HavenText.caption.copyWith(
                  color: HavenColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
  final VoidCallback? onTap;

  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isDisabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: HavenCard(
        radius: HavenRadius.button,
        width: double.infinity,
        semanticLabel: '$title. $subtitle',
        onTap: isDisabled ? null : onTap,
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
              child: Icon(icon, color: HavenColors.primary, size: 22),
            ),
            const SizedBox(width: HavenSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: HavenText.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: HavenText.caption),
                ],
              ),
            ),
            if (!isDisabled)
              const Icon(
                Icons.chevron_right,
                color: HavenColors.textTertiary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
