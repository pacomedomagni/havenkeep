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
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _saveAllItems();
  }

  Future<void> _saveAllItems() async {
    try {
      final bulkState = ref.read(bulkAddProvider);
      final user = ref.read(currentUserProvider).value;
      final homeId = bulkState.homeId;

      if (user == null || homeId == null) {
        setState(() {
          _isSaving = false;
          _hasError = true;
          _errorMessage = 'Missing user or home data';
        });
        return;
      }

      final allItems = bulkState.allItems;

      // Create items one by one
      for (final bulkItem in allItems) {
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
      }

      if (mounted) {
        setState(() => _isSaving = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _hasError = true;
          _errorMessage = ErrorHandler.getUserMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bulkState = ref.watch(bulkAddProvider);

    if (_isSaving) {
      return Scaffold(
        backgroundColor: HavenColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: HavenColors.primary,
              ),
              const SizedBox(height: HavenSpacing.lg),
              Text(
                'Saving ${bulkState.totalItemCount} items...',
                style: const TextStyle(
                  fontSize: 18,
                  color: HavenColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasError) {
      return Scaffold(
        backgroundColor: HavenColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(HavenSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: HavenColors.expired,
                ),
                const SizedBox(height: HavenSpacing.md),
                const Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: HavenColors.textPrimary,
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: HavenColors.textSecondary),
                ),
                const SizedBox(height: HavenSpacing.lg),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isSaving = true;
                      _hasError = false;
                    });
                    _saveAllItems();
                  },
                  child: const Text('Retry'),
                ),
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
