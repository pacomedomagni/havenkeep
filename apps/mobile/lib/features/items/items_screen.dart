import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';

/// Items list screen (Screen 4.1).
///
/// Shows all tracked items with:
/// - Search bar
/// - Status filter chips (All, Active, Expiring, Expired)
/// - Item cards sorted by warranty end date
class ItemsScreen extends ConsumerWidget {
  const ItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Items'),
      ),
      body: items.when(
        data: (itemList) {
          if (itemList.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: HavenColors.textTertiary,
                  ),
                  SizedBox(height: HavenSpacing.md),
                  Text(
                    'No items yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: HavenColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: HavenSpacing.xs),
                  Text(
                    'Tap + to add your first item',
                    style: TextStyle(color: HavenColors.textTertiary),
                  ),
                ],
              ),
            );
          }

          // TODO: Add search bar and filter chips
          return ListView.builder(
            padding: const EdgeInsets.all(HavenSpacing.md),
            itemCount: itemList.length,
            itemBuilder: (context, index) {
              final item = itemList[index];
              return Card(
                margin: const EdgeInsets.only(bottom: HavenSpacing.sm),
                child: ListTile(
                  title: Text(item.name),
                  subtitle: Text(
                    item.brand ?? item.category.displayLabel,
                  ),
                  trailing: Text(
                    item.computedWarrantyStatus.displayLabel,
                    style: TextStyle(
                      color: switch (item.computedWarrantyStatus) {
                        _ when item.computedWarrantyStatus.name == 'active' =>
                          HavenColors.active,
                        _ when item.computedWarrantyStatus.name == 'expiring' =>
                          HavenColors.expiring,
                        _ => HavenColors.expired,
                      },
                    ),
                  ),
                  onTap: () => context.push('/items/${item.id}'),
                ),
              );
            },
          );
        },
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
