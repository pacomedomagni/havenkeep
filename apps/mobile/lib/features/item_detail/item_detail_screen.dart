import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';
import 'share_claim_sheet.dart';

/// Item detail screen with accordion sections (Screen 6.1/6.2).
///
/// Shows:
/// - Hero section (category icon + name + warranty status card)
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/items/$itemId/edit'),
          ),
          _OverflowMenu(itemId: itemId),
        ],
      ),
      body: itemAsync.when(
        data: (item) => _ItemDetailBody(item: item, itemId: itemId),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Error loading item: $error',
            style: const TextStyle(color: HavenColors.expired),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overflow menu (Archive / Delete)
// ---------------------------------------------------------------------------

class _OverflowMenu extends ConsumerWidget {
  final String itemId;

  const _OverflowMenu({required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      color: HavenColors.elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HavenRadius.card),
      ),
      onSelected: (value) async {
        switch (value) {
          case 'archive':
            final confirmed = await showHavenConfirmDialog(
              context,
              title: 'Archive item?',
              body:
                  'This item will be moved to your archive. You can restore it later.',
              confirmLabel: 'Archive',
            );
            if (confirmed && context.mounted) {
              await ref.read(itemsProvider.notifier).archiveItem(itemId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Item archived')),
                );
                context.go(AppRoutes.items);
              }
            }
            break;
          case 'delete':
            final confirmed = await showHavenConfirmDialog(
              context,
              title: 'Delete item?',
              body:
                  'This action cannot be undone. All data for this item will be permanently removed.',
              confirmLabel: 'Delete',
              isDestructive: true,
            );
            if (confirmed && context.mounted) {
              await ref.read(itemsProvider.notifier).deleteItem(itemId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Item deleted')),
                );
                context.go(AppRoutes.items);
              }
            }
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'archive',
          child: Row(
            children: [
              Icon(Icons.archive_outlined, size: 20, color: HavenColors.textSecondary),
              SizedBox(width: HavenSpacing.sm),
              Text('Archive'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: HavenColors.expired),
              SizedBox(width: HavenSpacing.sm),
              Text('Delete', style: TextStyle(color: HavenColors.expired)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Main body
// ---------------------------------------------------------------------------

class _ItemDetailBody extends StatelessWidget {
  final Item item;
  final String itemId;

  const _ItemDetailBody({required this.item, required this.itemId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = item.computedWarrantyStatus;
    final days = item.computedDaysRemaining;

    final statusColor = switch (status) {
      WarrantyStatus.active => HavenColors.active,
      WarrantyStatus.expiring => HavenColors.expiring,
      WarrantyStatus.expired => HavenColors.expired,
    };

    // Count how many detail fields are populated for initial expansion logic.
    final populatedFields = [
      item.brand,
      item.modelNumber,
      item.serialNumber,
      item.room,
      item.price,
      item.store,
      item.warrantyProvider,
    ].where((v) => v != null).length + 2; // category + warrantyType always exist

    return SingleChildScrollView(
      padding: const EdgeInsets.all(HavenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ----------------------------------------------------------------
          // Hero section (always visible)
          // ----------------------------------------------------------------

          // Category icon container
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: HavenColors.elevated,
              borderRadius: BorderRadius.circular(HavenRadius.card),
            ),
            child: Center(
              child: CategoryIcon.widget(item.category, size: 64),
            ),
          ),

          const SizedBox(height: HavenSpacing.md),

          // Item name
          Text(
            [if (item.brand != null) item.brand!, item.name]
                .join(' '),
            style: theme.textTheme.headlineMedium,
          ),

          // Model number
          if (item.modelNumber != null) ...[
            const SizedBox(height: HavenSpacing.xs),
            Text(
              item.modelNumber!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: HavenColors.textSecondary,
              ),
            ),
          ],

          const SizedBox(height: HavenSpacing.md),

          // Warranty status card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(HavenSpacing.md),
            decoration: BoxDecoration(
              color: HavenColors.elevated,
              borderRadius: BorderRadius.circular(HavenRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'WARRANTY STATUS'),
                const SizedBox(height: HavenSpacing.sm),

                // Status row
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: HavenSpacing.sm),
                    Text(
                      status.displayLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: HavenSpacing.sm),

                // Time remaining
                Text(
                  _buildTimeRemainingText(status, days),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),

                const SizedBox(height: HavenSpacing.sm),

                // Expiry date
                if (item.warrantyEndDate != null)
                  Text(
                    status == WarrantyStatus.expired
                        ? 'Expired ${_formatDate(item.warrantyEndDate!)}'
                        : 'Expires ${_formatDate(item.warrantyEndDate!)}',
                    style: theme.textTheme.bodyMedium,
                  ),

                const SizedBox(height: HavenSpacing.xs),

                // Purchase info
                Text(
                  'Purchased: ${_formatDate(item.purchaseDate)}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: HavenSpacing.xs),
                Text(
                  'Duration: ${_formatDuration(item.warrantyMonths)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),

          const SizedBox(height: HavenSpacing.lg),

          // ----------------------------------------------------------------
          // DETAILS accordion
          // ----------------------------------------------------------------

          HavenAccordion(
            title: 'Details',
            initiallyExpanded: populatedFields >= 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Column(
                children: [
                  _DetailRow('Brand', item.brand),
                  _DetailRow('Model', item.modelNumber),
                  _DetailRow('Serial', item.serialNumber),
                  _DetailRow('Category', item.category.displayLabel),
                  _DetailRow('Room', item.room?.displayLabel),
                  _DetailRow(
                    'Price',
                    item.price != null
                        ? '\$${item.price!.toStringAsFixed(2)}'
                        : null,
                  ),
                  _DetailRow('Store', item.store),
                  _DetailRow('Warranty', item.warrantyType.displayLabel),
                  _DetailRow('Provider', item.warrantyProvider),
                ],
              ),
            ),
          ),

          const SizedBox(height: HavenSpacing.sm),

          // ----------------------------------------------------------------
          // DOCUMENTS accordion
          // ----------------------------------------------------------------

          HavenAccordion(
            title: 'Documents',
            trailing: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: HavenSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: HavenColors.surface,
                borderRadius: BorderRadius.circular(HavenRadius.chip),
              ),
              child: Text(
                '0',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: HavenColors.textTertiary,
                ),
              ),
            ),
            initiallyExpanded: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Column(
                children: [
                  const Text(
                    'No documents yet',
                    style: TextStyle(color: HavenColors.textTertiary),
                  ),
                  const SizedBox(height: HavenSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: null, // Phase 2
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Document'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HavenColors.textTertiary,
                      side: const BorderSide(color: HavenColors.border),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: HavenSpacing.sm),

          // ----------------------------------------------------------------
          // CLAIM HELP accordion
          // ----------------------------------------------------------------

          HavenAccordion(
            title: 'Claim Help',
            initiallyExpanded: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      final brand = item.brand ?? item.name;
                      final query = Uri.encodeComponent('$brand warranty support');
                      final url = 'https://www.google.com/search?q=$query';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Search: $url')),
                      );
                    },
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(
                      'Search ${item.brand ?? item.name} Warranty Support',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HavenColors.secondary,
                      side: const BorderSide(color: HavenColors.border),
                      padding: const EdgeInsets.symmetric(
                        vertical: HavenSpacing.sm + 4,
                        horizontal: HavenSpacing.md,
                      ),
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () {
                      ShareClaimSheet.show(context, item);
                    },
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share Claim Info'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HavenColors.secondary,
                      side: const BorderSide(color: HavenColors.border),
                      padding: const EdgeInsets.symmetric(
                        vertical: HavenSpacing.sm + 4,
                        horizontal: HavenSpacing.md,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: HavenSpacing.sm),

          // ----------------------------------------------------------------
          // NOTES accordion
          // ----------------------------------------------------------------

          HavenAccordion(
            title: 'Notes',
            initiallyExpanded: item.notes != null && item.notes!.isNotEmpty,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Text(
                item.notes != null && item.notes!.isNotEmpty
                    ? item.notes!
                    : 'No notes yet',
                style: TextStyle(
                  color: item.notes != null && item.notes!.isNotEmpty
                      ? HavenColors.textPrimary
                      : HavenColors.textTertiary,
                ),
              ),
            ),
          ),

          // Bottom spacing
          const SizedBox(height: HavenSpacing.xxl),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  String _buildTimeRemainingText(WarrantyStatus status, int days) {
    switch (status) {
      case WarrantyStatus.active:
        final months = days ~/ 30;
        if (months > 0) {
          return '$months ${months == 1 ? 'month' : 'months'} remaining';
        }
        return '$days ${days == 1 ? 'day' : 'days'} remaining';
      case WarrantyStatus.expiring:
        return '$days ${days == 1 ? 'day' : 'days'} remaining';
      case WarrantyStatus.expired:
        final absDays = days.abs();
        return 'Expired $absDays ${absDays == 1 ? 'day' : 'days'} ago';
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }

  String _formatDuration(int months) {
    if (months >= 12 && months % 12 == 0) {
      final years = months ~/ 12;
      return '$years ${years == 1 ? 'year' : 'years'}';
    }
    if (months >= 12) {
      final years = months ~/ 12;
      final rem = months % 12;
      return '$years ${years == 1 ? 'year' : 'years'} $rem ${rem == 1 ? 'month' : 'months'}';
    }
    return '$months ${months == 1 ? 'month' : 'months'}';
  }
}

// ---------------------------------------------------------------------------
// Detail row (two-column label / value)
// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HavenSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: HavenColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '\u2014', // em-dash for null
              style: const TextStyle(
                fontSize: 14,
                color: HavenColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
