import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/services/partners_repository.dart';

/// Lists every partner gift the current user has redeemed. The list is read
/// from `GET /api/v1/users/me/gifts` and shows status, partner, premium
/// duration, and remaining days.
class RecentGiftsScreen extends ConsumerStatefulWidget {
  const RecentGiftsScreen({super.key});

  @override
  ConsumerState<RecentGiftsScreen> createState() => _RecentGiftsScreenState();
}

class _RecentGiftsScreenState extends ConsumerState<RecentGiftsScreen> {
  late Future<List<PartnerGift>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<PartnerGift>> _fetch() async {
    final repo = PartnersRepository(ref.read(apiClientProvider));
    final raw = await repo.getMyGifts();
    return raw.map(PartnerGift.fromJson).toList();
  }

  Future<void> _refresh() async {
    final next = _fetch();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Your gifts'),
        backgroundColor: HavenColors.background,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<PartnerGift>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorState(
                error: snap.error!,
                onRetry: _refresh,
              );
            }
            final gifts = snap.data ?? [];
            if (gifts.isEmpty) {
              return const _EmptyState();
            }
            return ListView.separated(
              padding: const EdgeInsets.all(HavenSpacing.md),
              itemCount: gifts.length,
              separatorBuilder: (_, __) => const SizedBox(height: HavenSpacing.sm),
              itemBuilder: (_, i) => _GiftCard(gift: gifts[i]),
            );
          },
        ),
      ),
    );
  }
}

class _GiftCard extends StatelessWidget {
  final PartnerGift gift;
  const _GiftCard({required this.gift});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (gift.status) {
      PartnerGiftStatus.activated => HavenColors.active,
      PartnerGiftStatus.expired => HavenColors.expired,
      _ => HavenColors.expiring,
    };
    final partnerLabel = gift.homebuyerName.isNotEmpty
        ? gift.homebuyerName
        : 'HavenKeep partner';
    final daysRemaining = gift.expiresAt?.difference(DateTime.now()).inDays;
    return Container(
      decoration: BoxDecoration(
        color: HavenColors.elevated,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      padding: const EdgeInsets.all(HavenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  partnerLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: HavenColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  gift.status.name,
                  style: TextStyle(fontSize: 12, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            '${gift.premiumMonths} month${gift.premiumMonths == 1 ? '' : 's'} of Premium',
            style: const TextStyle(color: HavenColors.textSecondary, fontSize: 14),
          ),
          if (daysRemaining != null && daysRemaining > 0) ...[
            const SizedBox(height: HavenSpacing.xs),
            Text(
              '$daysRemaining day${daysRemaining == 1 ? '' : 's'} remaining',
              style: const TextStyle(color: HavenColors.textTertiary, fontSize: 12),
            ),
          ] else if (daysRemaining != null && daysRemaining <= 0) ...[
            const SizedBox(height: HavenSpacing.xs),
            const Text(
              'Expired',
              style: TextStyle(color: HavenColors.textTertiary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView keeps RefreshIndicator working even when empty.
      padding: const EdgeInsets.all(HavenSpacing.lg),
      children: const [
        SizedBox(height: 80),
        Icon(Icons.card_giftcard, size: 56, color: HavenColors.textTertiary),
        SizedBox(height: HavenSpacing.md),
        Text(
          'No gifts yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: HavenColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: HavenSpacing.sm),
        Text(
          'When a partner sends you a closing gift, it shows up here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: HavenColors.textSecondary, fontSize: 14),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(HavenSpacing.lg),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 56, color: HavenColors.expired),
        const SizedBox(height: HavenSpacing.md),
        const Text(
          'Could not load your gifts',
          textAlign: TextAlign.center,
          style: TextStyle(color: HavenColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: HavenSpacing.sm),
        Text(
          '$error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: HavenColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: HavenSpacing.md),
        Center(
          child: OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ),
      ],
    );
  }
}
