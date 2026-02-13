import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/items_provider.dart';
import '../../../core/router/router.dart';
import '../../../core/utils/error_handler.dart';
import 'bulk_add_provider.dart';

/// Bulk-add complete screen (Screen 2.5).
///
/// Shows success animation and summary after saving all items.
class BulkAddCompleteScreen extends ConsumerStatefulWidget {
  const BulkAddCompleteScreen({super.key});

  @override
  ConsumerState<BulkAddCompleteScreen> createState() =>
      _BulkAddCompleteScreenState();
}

class _BulkAddCompleteScreenState
    extends ConsumerState<BulkAddCompleteScreen> {
  bool _isSaving = true;
  int _savedCount = 0;
  int _totalCount = 0;
  final List<String> _failedItems = [];

  @override
  void initState() {
    super.initState();
    _saveAllItems();
  }

  Future<void> _saveAllItems() async {
    final bulkState = ref.read(bulkAddProvider);
    final user = ref.read(currentUserProvider).value;
    final homeId = bulkState.homeId;

    if (user == null || homeId == null) {
      setState(() {
        _isSaving = false;
        _failedItems.add('Missing user or home data');
      });
      return;
    }

    final allItems = bulkState.allItems;
    setState(() {
      _totalCount = allItems.length;
      _savedCount = 0;
      _failedItems.clear();
    });

    // Create items one by one, tracking individual success/failure
    for (final bulkItem in allItems) {
      try {
        final item = Item(
          id: '',
          homeId: homeId,
          userId: user.id,
          name: bulkItem.name,
          brand: bulkItem.brand?.isNotEmpty == true ? bulkItem.brand : null,
          category: bulkItem.category,
          room: bulkItem.room,
          purchaseDate: bulkItem.purchaseDate,
          warrantyMonths: bulkItem.warrantyMonths,
          addedVia: ItemAddedVia.bulk_setup,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await ref.read(itemsProvider.notifier).addItem(item);
        if (mounted) {
          setState(() => _savedCount++);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _failedItems.add(bulkItem.name));
        }
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _retryFailed() async {
    final bulkState = ref.read(bulkAddProvider);
    final user = ref.read(currentUserProvider).value;
    final homeId = bulkState.homeId;
    if (user == null || homeId == null) return;

    final failedNames = List<String>.from(_failedItems);
    final allItems = bulkState.allItems
        .where((i) => failedNames.contains(i.name))
        .toList();

    setState(() {
      _isSaving = true;
      _totalCount = allItems.length;
      _savedCount = 0;
      _failedItems.clear();
    });

    for (final bulkItem in allItems) {
      try {
        final item = Item(
          id: '',
          homeId: homeId,
          userId: user.id,
          name: bulkItem.name,
          brand: bulkItem.brand?.isNotEmpty == true ? bulkItem.brand : null,
          category: bulkItem.category,
          room: bulkItem.room,
          purchaseDate: bulkItem.purchaseDate,
          warrantyMonths: bulkItem.warrantyMonths,
          addedVia: ItemAddedVia.bulk_setup,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await ref.read(itemsProvider.notifier).addItem(item);
        if (mounted) {
          setState(() => _savedCount++);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _failedItems.add(bulkItem.name));
        }
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bulkState = ref.watch(bulkAddProvider);

    if (_isSaving) {
      final progress = _totalCount > 0 ? _savedCount / _totalCount : 0.0;
      return Scaffold(
        backgroundColor: HavenColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: HavenColors.primary,
                ),
                const SizedBox(height: HavenSpacing.lg),
                Text(
                  'Saving item $_savedCount of $_totalCount...',
                  style: const TextStyle(
                    fontSize: 18,
                    color: HavenColors.textSecondary,
                  ),
                ),
                const SizedBox(height: HavenSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: HavenColors.surface,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      HavenColors.primary,
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Partial failure: some items saved, some failed
    if (_failedItems.isNotEmpty) {
      return Scaffold(
        backgroundColor: HavenColors.background,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HavenSpacing.lg),
            child: Column(
              children: [
                const SizedBox(height: HavenSpacing.xxl),
                Icon(
                  _savedCount > 0 ? Icons.warning_amber_rounded : Icons.error_outline,
                  size: 64,
                  color: _savedCount > 0 ? HavenColors.expiring : HavenColors.expired,
                ),
                const SizedBox(height: HavenSpacing.md),
                Text(
                  _savedCount > 0
                      ? '$_savedCount of ${_savedCount + _failedItems.length} Items Saved'
                      : 'Could Not Save Items',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: HavenColors.textPrimary,
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
                Text(
                  '${_failedItems.length} ${_failedItems.length == 1 ? 'item' : 'items'} failed to save:',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: HavenColors.textSecondary),
                ),
                const SizedBox(height: HavenSpacing.md),
                // List of failed items
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(HavenSpacing.md),
                  decoration: BoxDecoration(
                    color: HavenColors.surface,
                    borderRadius: BorderRadius.circular(HavenRadius.card),
                    border: Border.all(color: HavenColors.border),
                  ),
                  child: Column(
                    children: _failedItems.map((name) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: HavenSpacing.xs),
                        child: Row(
                          children: [
                            const Icon(Icons.close, size: 16, color: HavenColors.expired),
                            const SizedBox(width: HavenSpacing.sm),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: HavenColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: HavenSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _retryFailed,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: Text('Retry ${_failedItems.length} Failed ${_failedItems.length == 1 ? 'Item' : 'Items'}'),
                  ),
                ),
                if (_savedCount > 0) ...[
                  const SizedBox(height: HavenSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () {
                        ref.read(bulkAddProvider.notifier).reset();
                        context.go(AppRoutes.dashboard);
                      },
                      child: const Text('Continue to Dashboard'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Success state
    final summary = bulkState.roomSummary;

    return Scaffold(
      backgroundColor: HavenColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(HavenSpacing.lg),
          child: Column(
            children: [
              const SizedBox(height: HavenSpacing.xxl),

              // Success icon
              const Icon(
                Icons.check_circle,
                size: 80,
                color: HavenColors.active,
              ),

              const SizedBox(height: HavenSpacing.lg),

              // Headline
              const Text(
                'Home Setup Complete!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: HavenColors.textPrimary,
                ),
              ),

              const SizedBox(height: HavenSpacing.sm),

              // Summary
              Text(
                'You added ${bulkState.totalItemCount} items across ${bulkState.roomsWithItemsCount} rooms',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: HavenColors.textSecondary,
                ),
              ),

              const SizedBox(height: HavenSpacing.lg),

              // Room breakdown
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(HavenSpacing.md),
                decoration: BoxDecoration(
                  color: HavenColors.surface,
                  borderRadius: BorderRadius.circular(HavenRadius.card),
                  border: Border.all(color: HavenColors.border),
                ),
                child: Column(
                  children: summary.entries.map((entry) {
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: HavenSpacing.xs),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 14,
                              color: HavenColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${entry.value}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: HavenColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: HavenSpacing.lg),

              // Encouragement
              const Text(
                'You can add receipts, model numbers, and more details anytime.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: HavenColors.textTertiary,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: HavenSpacing.xl),

              // Go to Dashboard button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    ref.read(bulkAddProvider.notifier).reset();
                    context.go(AppRoutes.dashboard);
                  },
                  child: const Text('Go to Dashboard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
