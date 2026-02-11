import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

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
        HapticFeedback.lightImpact();
        onTap?.call();
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              HavenColors.accent,
              HavenColors.accentSecondary,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
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
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: HavenColors.textPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
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
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$warrantyHealth%',
                        style: const TextStyle(
                          color: HavenColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Health',
                        style: TextStyle(
                          color: HavenColors.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Total value
            Text(
              'Total Value Protected',
              style: TextStyle(
                color: HavenColors.textPrimary.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              '\$${_formatCurrency(totalValue)}',
              style: const TextStyle(
                color: HavenColors.textPrimary,
                fontSize: 40,
                fontWeight: FontWeight.bold,
                height: 1,
                letterSpacing: -1,
              ),
            ),

            const SizedBox(height: 20),

            // Stats row
            Row(
              children: [
                Expanded(
                  child: _buildStat(
                    icon: Icons.inventory_2_outlined,
                    value: '$totalItems',
                    label: totalItems == 1 ? 'Item' : 'Items',
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
              style: TextStyle(
                color: HavenColors.textPrimary.withValues(alpha: 0.85),
                fontSize: 13,
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
            Text(
              value,
              style: const TextStyle(
                color: HavenColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: HavenColors.textPrimary.withValues(alpha: 0.8),
            fontSize: 12,
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
            Text(
              'Warranty Health',
              style: TextStyle(
                color: HavenColors.textPrimary.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '$warrantyHealth%',
              style: const TextStyle(
                color: HavenColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
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

  String _formatCurrency(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    } else {
      return value.toStringAsFixed(0);
    }
  }
}
