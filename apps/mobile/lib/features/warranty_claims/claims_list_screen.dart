import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/warranty_claims_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/haven_loader.dart';

/// Warranty claims list — savings hero card on top, claims as
/// [HavenListItem] rows, community savings feed below. Every visual
/// element routes through the shared design system.
class ClaimsListScreen extends ConsumerWidget {
  const ClaimsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claimsAsync = ref.watch(claimsProvider);
    final savingsAsync = ref.watch(claimSavingsProvider);
    final feedAsync = ref.watch(savingsFeedProvider);
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      backgroundColor: HavenColors.canvas,
      appBar: const HavenAppBar(title: 'Warranty Claims'),
      body: claimsAsync.when(
        loading: () => const Center(child: HavenLoader()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(HavenSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ErrorHandler.getUserMessage(e),
                  style: HavenText.bodySecondary,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: HavenSpacing.md),
                HavenButton.tertiary(
                  label: 'Try again',
                  onPressed: () => ref.invalidate(claimsProvider),
                  leadingIcon: Icons.refresh,
                ),
              ],
            ),
          ),
        ),
        data: (claims) {
          if (claims.isEmpty) {
            return HavenEmptyState(
              icon: Icons.shield_outlined,
              title: 'No warranty claims yet',
              body: 'File a claim when something breaks under warranty '
                  'and track repairs, refunds, and savings here.',
              primaryAction: HavenEmptyAction(
                label: 'Pick an item to file a claim',
                icon: Icons.inventory_2_outlined,
                onPressed: () => context.push('/items'),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(HavenSpacing.md),
            children: [
              // Savings hero card
              savingsAsync.when(
                data: (savings) {
                  final totalSaved =
                      (savings['total_savings'] as num?)?.toDouble() ?? 0;
                  final totalClaims =
                      (savings['total_claims'] as num?)?.toInt() ?? 0;
                  return _SavingsHeroCard(
                    totalSaved: totalSaved,
                    totalClaims: totalClaims,
                  );
                },
                loading: () => const HavenCard(
                  child: SizedBox(
                    height: 96,
                    child: Center(child: SkeletonBox(width: 160, height: 28)),
                  ),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Claims list — each row is its own HavenListItem (card style).
              for (final claim in claims) ...[
                _ClaimRow(claim: claim, dateFormat: dateFormat),
                const SizedBox(height: HavenSpacing.sm),
              ],

              // Community savings feed
              feedAsync.when(
                data: (feed) {
                  if (feed.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: HavenSpacing.lg),
                      const SectionHeader(title: 'COMMUNITY SAVINGS'),
                      const SizedBox(height: HavenSpacing.sm),
                      for (final entry in feed) ...[
                        _SavingsFeedRow(entry: entry),
                        const SizedBox(height: HavenSpacing.sm),
                      ],
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: HavenSpacing.md),
            ],
          );
        },
      ),
    );
  }
}

class _SavingsHeroCard extends StatelessWidget {
  final double totalSaved;
  final int totalClaims;

  const _SavingsHeroCard({
    required this.totalSaved,
    required this.totalClaims,
  });

  @override
  Widget build(BuildContext context) {
    return HavenCard.highlight(
      glow: HavenColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL SAVINGS',
            style: HavenText.badge.copyWith(
              color: HavenColors.textPrimary.withValues(alpha: 0.78),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: HavenSpacing.sm),
          Text(
            Money.format(totalSaved),
            style: HavenText.stat.copyWith(fontSize: 34),
          ),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            '$totalClaims claim${totalClaims == 1 ? '' : 's'} filed',
            style: HavenText.bodySecondary.copyWith(
              color: HavenColors.textPrimary.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaimRow extends ConsumerWidget {
  final WarrantyClaim claim;
  final DateFormat dateFormat;

  const _ClaimRow({required this.claim, required this.dateFormat});

  Color _statusColor(ClaimStatus status) => switch (status) {
        ClaimStatus.filed => HavenColors.expiring,
        ClaimStatus.inReview => HavenColors.primary,
        ClaimStatus.approved => HavenColors.active,
        ClaimStatus.settled => HavenColors.active,
        ClaimStatus.closed => HavenColors.textSecondary,
        ClaimStatus.denied => HavenColors.expired,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _statusColor(claim.status);
    final itemLabel = claim.itemBrand != null
        ? '${claim.itemBrand} ${claim.itemName ?? ''}'.trim()
        : claim.itemName ?? 'Item';

    final subtitleParts = <String>[
      if (claim.issueDescription != null) claim.issueDescription!,
    ];
    final supplementaryParts = <String>[
      dateFormat.format(claim.claimDate),
      if (claim.amountSaved > 0) 'Saved ${Money.format(claim.amountSaved)}',
    ];

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
      child: HavenListItem(
        title: itemLabel,
        subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' · '),
        supplementary: supplementaryParts.join('  ·  '),
        accent: color,
        trailing: _StatusBadge(color: color, label: claim.status.displayLabel),
        onTap: () => context.push('/items/${claim.itemId}'),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Color color;
  final String label;
  const _StatusBadge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HavenSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(HavenRadius.chip),
      ),
      child: Text(
        label,
        style: HavenText.badge.copyWith(color: color, letterSpacing: 0),
      ),
    );
  }
}

class _SavingsFeedRow extends StatelessWidget {
  final Map<String, dynamic> entry;

  const _SavingsFeedRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final amount = (entry['amount_saved'] as num?)?.toDouble() ?? 0;
    final city = entry['user_city'] as String?;
    final state = entry['user_state'] as String?;
    final displayText = entry['display_text'] as String?;
    final claimType = entry['claim_type'] as String?;

    final location =
        [city, state].where((s) => s != null && s.isNotEmpty).join(', ');
    final subtitle = displayText ?? claimType ?? 'Warranty claim';

    return HavenListItem(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: HavenColors.active.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.savings_outlined,
          color: HavenColors.active,
          size: 18,
        ),
      ),
      title: subtitle,
      subtitle: location.isEmpty ? null : location,
      trailing: Text(
        '${Money.formatWhole(amount)} saved',
        style: HavenText.meta.copyWith(
          color: HavenColors.active,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
