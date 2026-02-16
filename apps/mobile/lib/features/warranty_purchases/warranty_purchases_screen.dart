import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/warranty_purchases_provider.dart';
import '../../core/router/router.dart';
import '../../core/utils/error_handler.dart';

/// List of extended warranty purchases for the current user.
class WarrantyPurchasesScreen extends ConsumerWidget {
  const WarrantyPurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchasesAsync = ref.watch(warrantyPurchasesProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Warranty Coverage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(warrantyPurchasesProvider.notifier).refresh(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.addWarrantyPurchase),
        backgroundColor: HavenColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(HavenSpacing.md),
        children: [
          const SectionHeader(title: 'YOUR COVERAGE'),
          const SizedBox(height: HavenSpacing.sm),
          purchasesAsync.when(
            data: (purchases) {
              if (purchases.isEmpty) {
                return const _EmptyState();
              }
              return Column(
                children: purchases
                    .map((purchase) => _PurchaseCard(purchase: purchase))
                    .toList(),
              );
            },
            loading: () => const _LoadingState(),
            error: (err, _) => _ErrorState(
              message: ErrorHandler.getUserMessage(err),
              onRetry: () => ref.read(warrantyPurchasesProvider.notifier).refresh(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseCard extends ConsumerWidget {
  final WarrantyPurchase purchase;

  const _PurchaseCard({required this.purchase});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = switch (purchase.status) {
      WarrantyPurchaseStatus.active => HavenColors.active,
      WarrantyPurchaseStatus.pending => HavenColors.expiring,
      WarrantyPurchaseStatus.expired => HavenColors.expired,
      WarrantyPurchaseStatus.cancelled => HavenColors.textTertiary,
      WarrantyPurchaseStatus.claimed => HavenColors.primary,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: HavenSpacing.sm),
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  purchase.itemName ?? 'Warranty Coverage',
                  style: const TextStyle(
                    color: HavenColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: HavenSpacing.sm,
                  vertical: HavenSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(HavenRadius.chip),
                ),
                child: Text(
                  purchase.status.displayLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            '${purchase.provider} • ${purchase.planName}',
            style: const TextStyle(
              color: HavenColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            'Start ${_formatDate(purchase.startsAt)} • '
            'End ${_formatDate(purchase.expiresAt)}',
            style: const TextStyle(
              color: HavenColors.textTertiary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: HavenSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  NumberFormat.simpleCurrency().format(purchase.price),
                  style: const TextStyle(
                    color: HavenColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (purchase.status == WarrantyPurchaseStatus.active)
                TextButton(
                  onPressed: () => _confirmCancel(context, ref, purchase.id),
                  child: const Text('Cancel'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final confirmed = await showHavenConfirmDialog(
      context,
      title: 'Cancel coverage?',
      body: 'This will mark the warranty as cancelled.',
      confirmLabel: 'Cancel Warranty',
      isDestructive: true,
    );
    if (!confirmed) return;

    try {
      await ref.read(warrantyPurchasesProvider.notifier).cancelPurchase(id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Warranty cancelled')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
        );
      }
    }
  }
}

String _formatDate(DateTime date) {
  return DateFormat.yMMMd().format(date);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.lg),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Column(
        children: const [
          Icon(Icons.shield_outlined, color: HavenColors.textTertiary),
          SizedBox(height: HavenSpacing.sm),
          Text(
            'No coverage yet',
            style: TextStyle(
              color: HavenColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: HavenSpacing.xs),
          Text(
            'Add an extended warranty to track your coverage.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HavenColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(HavenSpacing.lg),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: HavenColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: HavenSpacing.sm),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
