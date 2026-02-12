import 'package:flutter/material.dart';
import 'theme.dart';

/// A banner widget that warns users about their free plan item limit.
///
/// Shows a progress bar and contextual message:
/// - Approaching limit (4): "You've used {n}/5 free items"
/// - At limit (5+): "Item limit reached. Archive old items or upgrade."
class ItemLimitBanner extends StatelessWidget {
  final int currentCount;
  final int maxCount;
  final VoidCallback? onArchive;
  final VoidCallback? onUpgrade;

  const ItemLimitBanner({
    super.key,
    required this.currentCount,
    this.maxCount = 5,
    this.onArchive,
    this.onUpgrade,
  });

  bool get _isAtLimit => currentCount >= maxCount;
  double get _progress => (currentCount / maxCount).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HavenSpacing.md),
      margin: const EdgeInsets.only(bottom: HavenSpacing.md),
      decoration: BoxDecoration(
        color: _isAtLimit
            ? HavenColors.expired.withValues(alpha: 0.1)
            : HavenColors.expiring.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isAtLimit
              ? HavenColors.expired.withValues(alpha: 0.3)
              : HavenColors.expiring.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header text
          Text(
            _isAtLimit
                ? 'Item limit reached'
                : "You've used $currentCount/$maxCount free items",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _isAtLimit ? HavenColors.expired : HavenColors.expiring,
            ),
          ),
          const SizedBox(height: HavenSpacing.sm),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: HavenColors.surface,
              valueColor: AlwaysStoppedAnimation(
                _isAtLimit ? HavenColors.expired : HavenColors.expiring,
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: HavenSpacing.sm),

          // Description
          Text(
            _isAtLimit
                ? 'Archive old items to free up space, or upgrade to Premium for unlimited items.'
                : '${maxCount - currentCount} items remaining on your free plan.',
            style: const TextStyle(
              fontSize: 12,
              color: HavenColors.textSecondary,
              height: 1.3,
            ),
          ),

          // Action links
          if (_isAtLimit) ...[
            const SizedBox(height: HavenSpacing.sm),
            Row(
              children: [
                if (onArchive != null)
                  Semantics(
                    button: true,
                    label: 'Archive Items',
                    child: InkWell(
                      onTap: onArchive,
                      child: const Text(
                        'Archive Items \u2192',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: HavenColors.secondary,
                        ),
                      ),
                    ),
                  ),
                if (onArchive != null && onUpgrade != null)
                  const SizedBox(width: HavenSpacing.lg),
                if (onUpgrade != null)
                  Semantics(
                    button: true,
                    label: 'Upgrade',
                    child: InkWell(
                      onTap: onUpgrade,
                      child: Text(
                        'Upgrade \u2192',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: HavenColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
