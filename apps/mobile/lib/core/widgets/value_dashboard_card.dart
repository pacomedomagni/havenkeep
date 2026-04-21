import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../utils/money_formatter.dart';
import '../../core/utils/haven_haptics.dart';

/// Enhanced dashboard card showing total value protected and warranty health.
class ValueDashboardCard extends StatelessWidget {
  final double totalValue;
  final int warrantyHealth; // 0-100 percentage
  final int totalItems;
  final int activeWarranties;
  final VoidCallback? onTap;

  const ValueDashboardCard({
    super.key,
    required this.totalValue,
    required this.warrantyHealth,
    required this.totalItems,
    required this.activeWarranties,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HavenHaptics.tap();
        onTap?.call();
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              HavenColors.accent,
              HavenColors.accentSecondary,
            ],
          ),
          borderRadius: BorderRadius.circular(HavenRadius.chip),
          boxShadow: [
            BoxShadow(
              color: HavenColors.accent.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(HavenSpacing.sm),
                  decoration: BoxDecoration(
                    color: HavenColors.textPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(HavenRadius.button),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: HavenColors.textPrimary,
                    size: 24,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: HavenColors.textPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(HavenRadius.chip),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$warrantyHealth%', style: HavenText.body.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      Text('Health', style: HavenText.caption.copyWith(color: HavenColors.textPrimary)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Total value
            Text(
              'Total Value Protected',
              style: HavenText.body.copyWith(
                fontWeight: FontWeight.w500,
                color: HavenColors.textPrimary.withValues(alpha: 0.9),
              ),
            ),

            const SizedBox(height: HavenSpacing.sm),

            Text(
              Money.formatCompact(totalValue),
              style: HavenText.hero.copyWith(letterSpacing: -1),
            ),

            const SizedBox(height: 20),

            // Stats row
            Row(
              children: [
                Expanded(
                  child: _buildStat(
                    icon: Icons.inventory_2_outlined,
                    value: '$totalItems',
                    label: totalItems == 1 ? 'Warranty' : 'Warranties',
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: HavenColors.textPrimary.withValues(alpha: 0.2),
                ),
                Expanded(
                  child: _buildStat(
                    icon: Icons.verified_user_outlined,
                    value: '$activeWarranties',
                    label: activeWarranties == 1 ? 'Active' : 'Active',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Health bar
            _buildHealthBar(),

            const SizedBox(height: 12),

            // Health message
            Text(
              _getHealthMessage(),
              style: HavenText.meta.copyWith(
                color: HavenColors.textPrimary.withValues(alpha: 0.85),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: HavenColors.textPrimary, size: 16),
            const SizedBox(width: 6),
            Text(value, style: HavenText.displayMedium),
          ],
        ),
        const SizedBox(height: HavenSpacing.xs),
        Text(
          label,
          style: HavenText.caption.copyWith(
            color: HavenColors.textPrimary.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildHealthBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Tooltip(
              message: '$activeWarranties of $totalItems items have active warranties',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Warranty Health',
                    style: HavenText.caption.copyWith(
                      fontWeight: FontWeight.w500,
                      color: HavenColors.textPrimary.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: HavenColors.textPrimary.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
            Text(
              '$warrantyHealth%',
              style: HavenText.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: HavenColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: HavenSpacing.xs),
        Text(
          '$activeWarranties of $totalItems warranties actively covered',
          style: HavenText.badge.copyWith(
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: HavenColors.textPrimary.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(HavenRadius.pill),
          child: LinearProgressIndicator(
            value: warrantyHealth / 100,
            minHeight: 8,
            backgroundColor: HavenColors.textPrimary.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              _getHealthColor(),
            ),
          ),
        ),
      ],
    );
  }

  Color _getHealthColor() {
    if (warrantyHealth >= 80) return HavenColors.active;
    if (warrantyHealth >= 50) return HavenColors.expiring;
    return HavenColors.expired;
  }

  String _getHealthMessage() {
    if (warrantyHealth >= 90) {
      return '🎉 Excellent! All your warranties are well-protected.';
    } else if (warrantyHealth >= 70) {
      return '👍 Good job! Most warranties are active.';
    } else if (warrantyHealth >= 50) {
      return '⚠️  Some warranties need attention.';
    } else {
      return '⚠️  Many warranties are expired or expiring soon.';
    }
  }

}
