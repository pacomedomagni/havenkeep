import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/warranty_claims_provider.dart';

/// Screen showing all warranty claims with a savings summary card.
class ClaimsListScreen extends ConsumerWidget {
  const ClaimsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claimsAsync = ref.watch(claimsProvider);
    final savingsAsync = ref.watch(claimSavingsProvider);
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(title: const Text('Warranty Claims')),
      body: claimsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error: $e', style: const TextStyle(color: HavenColors.textSecondary)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(claimsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (claims) {
          if (claims.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(HavenSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        size: 64, color: HavenColors.textTertiary),
                    const SizedBox(height: HavenSpacing.md),
                    const Text(
                      'No warranty claims yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: HavenColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.sm),
                    const Text(
                      'When you file a warranty claim,\nit will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: HavenColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(HavenSpacing.md),
            children: [
              // Savings summary card
              savingsAsync.when(
                data: (savings) {
                  final totalSaved = (savings['total_saved'] as num?)?.toDouble() ?? 0;
                  final totalClaims = (savings['total_claims'] as num?)?.toInt() ?? 0;

                  return Container(
                    padding: const EdgeInsets.all(HavenSpacing.lg),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [HavenColors.primary, Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(HavenRadius.card),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOTAL SAVINGS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: HavenSpacing.sm),
                        Text(
                          '\$${totalSaved.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: HavenSpacing.xs),
                        Text(
                          '$totalClaims claim${totalClaims == 1 ? '' : 's'} filed',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: HavenColors.elevated,
                    borderRadius: BorderRadius.circular(HavenRadius.card),
                  ),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Claims list
              ...claims.map((claim) => _ClaimCard(
                    claim: claim,
                    dateFormat: dateFormat,
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _ClaimCard extends ConsumerWidget {
  final WarrantyClaim claim;
  final DateFormat dateFormat;

  const _ClaimCard({required this.claim, required this.dateFormat});

  Color _statusColor(ClaimStatus status) => switch (status) {
        ClaimStatus.pending => HavenColors.expiring,
        ClaimStatus.in_progress => HavenColors.primary,
        ClaimStatus.completed => HavenColors.active,
        ClaimStatus.denied => HavenColors.expired,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _statusColor(claim.status);
    final itemLabel = claim.itemBrand != null
        ? '${claim.itemBrand} ${claim.itemName ?? ''}'.trim()
        : claim.itemName ?? 'Item';

    return Dismissible(
      key: Key(claim.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: HavenSpacing.lg),
        decoration: BoxDecoration(
          color: HavenColors.expired,
          borderRadius: BorderRadius.circular(HavenRadius.card),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showHavenConfirmDialog(
          context,
          title: 'Delete Claim?',
          body: 'This action cannot be undone.',
          confirmLabel: 'Delete',
          isDestructive: true,
        );
      },
      onDismissed: (_) {
        ref.read(claimsProvider.notifier).deleteClaim(claim.id);
      },
      child: GestureDetector(
        onTap: () => context.push('/items/${claim.itemId}'),
        child: Container(
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
                      itemLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: HavenColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HavenSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(HavenRadius.chip),
                    ),
                    child: Text(
                      claim.status.displayLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HavenSpacing.sm),
              if (claim.issueDescription != null) ...[
                Text(
                  claim.issueDescription!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: HavenColors.textSecondary,
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
              ],
              Row(
                children: [
                  Text(
                    dateFormat.format(claim.claimDate),
                    style: const TextStyle(
                      fontSize: 12,
                      color: HavenColors.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  if (claim.amountSaved > 0)
                    Text(
                      'Saved \$${claim.amountSaved.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: HavenColors.active,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
