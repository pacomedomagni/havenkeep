import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';
import '../../core/widgets/error_state_widget.dart';

/// Archived items screen.
///
/// Shows archived items with options to restore or permanently delete.
class ArchivedItemsScreen extends ConsumerWidget {
  const ArchivedItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedAsync = ref.watch(archivedItemsProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Archived Items'),
      ),
      body: archivedAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return _buildEmptyState();
          }
          return ListView.builder(
            padding: const EdgeInsets.all(HavenSpacing.md),
            itemCount: items.length,
            itemBuilder: (context, index) {
              return _ArchivedItemCard(item: items[index]);
            },
          );
        },
        loading: () => ListView(
          padding: const EdgeInsets.all(HavenSpacing.md),
          children: const [
            SkeletonCard(),
            SizedBox(height: HavenSpacing.sm),
            SkeletonCard(),
            SizedBox(height: HavenSpacing.sm),
            SkeletonCard(),
          ],
        ),
        error: (_, __) => ErrorStateWidget(
          message: 'Could not load archived items',
          onRetry: () => ref.invalidate(archivedItemsProvider),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.archive_outlined,
            size: 64,
            color: HavenColors.textTertiary,
          ),
          SizedBox(height: HavenSpacing.md),
          Text(
            'No archived items',
            style: TextStyle(
              fontSize: 18,
              color: HavenColors.textSecondary,
            ),
          ),
          SizedBox(height: HavenSpacing.xs),
          Text(
            'Items you archive will appear here.',
            style: TextStyle(
              color: HavenColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single archived item card with swipe actions.
class _ArchivedItemCard extends ConsumerWidget {
  final Item item;

  const _ArchivedItemCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HavenSpacing.sm),
      child: Semantics(
        hint: 'Swipe right to restore, swipe left to delete',
        child: Dismissible(
          key: ValueKey('archived-${item.id}'),
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: HavenSpacing.lg),
            decoration: BoxDecoration(
              color: HavenColors.active,
              borderRadius: HavenRadius.buttonRadius,
            ),
            child: const Row(
              children: [
                Icon(Icons.unarchive_outlined, color: HavenColors.textPrimary),
                SizedBox(width: HavenSpacing.sm),
                Text(
                  'Restore',
                  style: TextStyle(
                    color: HavenColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: HavenSpacing.lg),
            decoration: BoxDecoration(
              color: HavenColors.expired,
              borderRadius: HavenRadius.buttonRadius,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Delete',
                  style: TextStyle(
                    color: HavenColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: HavenSpacing.sm),
                Icon(Icons.delete_outline, color: HavenColors.textPrimary),
              ],
            ),
          ),
          confirmDismiss: (direction) async {
            HapticFeedback.mediumImpact();

            if (direction == DismissDirection.startToEnd) {
              // Restore
              await ref.read(itemsProvider.notifier).unarchiveItem(item.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${item.name} restored')),
                );
              }
              return true;
            } else {
              // Delete permanently
              final confirmed = await showHavenConfirmDialog(
                context,
                title: 'Delete permanently?',
                body:
                    'This will permanently remove "${item.name}". This cannot be undone.',
                confirmLabel: 'Delete',
                isDestructive: true,
              );
              if (confirmed) {
                await ref.read(itemsProvider.notifier).deleteItem(item.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${item.name} deleted')),
                  );
                }
                return true;
              }
              return false;
            }
          },
          child: Container(
            padding: const EdgeInsets.all(HavenSpacing.md),
            decoration: BoxDecoration(
              color: HavenColors.surface,
              borderRadius: HavenRadius.buttonRadius,
              border: Border.all(color: HavenColors.border),
            ),
            child: Row(
              children: [
                CategoryIcon.widget(item.category),
                const SizedBox(width: HavenSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.brand ?? ''} ${item.name}'.trim(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: HavenColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // TODO: Use dedicated archivedAt field when available
                      Text(
                        'Archived ${DateFormat.yMMMd().format(item.updatedAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: HavenColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.swipe_outlined,
                  color: HavenColors.textTertiary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
