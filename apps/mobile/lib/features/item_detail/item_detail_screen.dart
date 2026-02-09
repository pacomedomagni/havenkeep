import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../core/providers/items_provider.dart';

/// Item detail screen with accordion sections (Screen 6.1/6.2).
///
/// Shows:
/// - Hero section (image + warranty status badge + countdown)
/// - Collapsible Details section
/// - Collapsible Documents section
/// - Collapsible Claim Help section
/// - Collapsible Notes section
class ItemDetailScreen extends ConsumerWidget {
  final String itemId;

  const ItemDetailScreen({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemDetailProvider(itemId));

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Item Detail'),
        actions: [
          // TODO: Edit button, share button
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              // TODO: Navigate to edit screen
            },
          ),
        ],
      ),
      body: itemAsync.when(
        data: (item) => SingleChildScrollView(
          padding: const EdgeInsets.all(HavenSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(HavenSpacing.lg),
                decoration: BoxDecoration(
                  color: HavenColors.surface,
                  borderRadius: BorderRadius.circular(HavenRadius.card),
                ),
                child: Column(
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: HavenColors.textPrimary,
                      ),
                    ),
                    if (item.brand != null) ...[
                      const SizedBox(height: HavenSpacing.xs),
                      Text(
                        item.brand!,
                        style: const TextStyle(
                          fontSize: 16,
                          color: HavenColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: HavenSpacing.md),
                    // TODO: Warranty status badge + countdown
                    Text(
                      item.computedWarrantyStatus.displayLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: switch (item.computedWarrantyStatus.name) {
                          'active' => HavenColors.active,
                          'expiring' => HavenColors.expiring,
                          _ => HavenColors.expired,
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: HavenSpacing.md),

              // TODO: Accordion sections (Details, Documents, Claim Help, Notes)
              const Center(
                child: Text(
                  'Accordion sections coming soon',
                  style: TextStyle(color: HavenColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Error: $error',
            style: const TextStyle(color: HavenColors.expired),
          ),
        ),
      ),
    );
  }
}
