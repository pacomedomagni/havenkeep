import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../utils/money_formatter.dart';
import '../../core/utils/haven_haptics.dart';

/// The dashboard hero — the one unmissable thing at the top of Home.
///
/// Layout, Linear/Arc-style: a calm indigo→violet gradient surface with a
/// soft glow, the protected-value figure counting up on the left, a
/// health ring animating its sweep on the right, and the
/// active / expiring / expired breakdown as a tight tappable pill row
/// underneath. No emoji; the only color outside the gradient is the three
/// status dots.
class ValueDashboardCard extends StatelessWidget {
  final double totalValue;
  final int warrantyHealth; // 0-100
  final int totalItems;
  final int activeWarranties;
  final int expiringWarranties;
  final int expiredWarranties;
  final VoidCallback? onTap;
  final void Function(String filter)? onStatusTap;

  const ValueDashboardCard({
    super.key,
    required this.totalValue,
    required this.warrantyHealth,
    required this.totalItems,
    required this.activeWarranties,
    this.expiringWarranties = 0,
    this.expiredWarranties = 0,
    this.onTap,
    this.onStatusTap,
  });

  Color get _healthColor {
    if (warrantyHealth >= 80) return HavenColors.active;
    if (warrantyHealth >= 50) return HavenColors.expiring;
    return HavenColors.expired;
  }

  static Color _onGradient(double a) => Colors.white.withValues(alpha: a);

  @override
  Widget build(BuildContext context) {
    final hasBreakdown =
        activeWarranties + expiringWarranties + expiredWarranties > 0;
    final hasItems = totalItems > 0;

    return HavenCard.highlight(
      padding: const EdgeInsets.fromLTRB(
          HavenSpacing.lg, HavenSpacing.lg, HavenSpacing.lg, HavenSpacing.md),
      glow: HavenColors.primary,
      onTap: onTap == null
          ? null
          : () {
              HavenHaptics.tap();
              onTap!();
            },
      semanticLabel:
          'Total value protected ${Money.formatCompact(totalValue)}, '
          'warranty health $warrantyHealth percent, '
          '$totalItems ${totalItems == 1 ? "warranty" : "warranties"} tracked',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: value figure ┊ health ring ──────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 16, color: _onGradient(0.9)),
                        const SizedBox(width: HavenSpacing.xs + 2),
                        Text('TOTAL VALUE PROTECTED',
                            style: HavenText.overline
                                .copyWith(color: _onGradient(0.85))),
                      ],
                    ),
                    const SizedBox(height: HavenSpacing.sm),
                    CountUpText(
                      value: totalValue,
                      prefix: '\$',
                      style: HavenText.hero.copyWith(color: Colors.white),
                      format: _compactDollars,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalItems ${totalItems == 1 ? "item" : "items"} tracked',
                      style: HavenText.meta.copyWith(color: _onGradient(0.85)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HavenSpacing.md),
              if (hasItems)
                Column(
                  children: [
                    HavenStatRing(
                      value: warrantyHealth / 100,
                      size: 78,
                      strokeWidth: 7,
                      color: _healthColor,
                      trackColor: _onGradient(0.22),
                      center: CountUpText(
                        value: warrantyHealth,
                        suffix: '%',
                        style: HavenText.titleMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.xs),
                    Text(
                      'health',
                      style: HavenText.caption
                          .copyWith(color: _onGradient(0.8)),
                    ),
                  ],
                ),
            ],
          ),

          if (hasBreakdown) ...[
            const SizedBox(height: HavenSpacing.md),
            Divider(height: 1, color: _onGradient(0.18)),
            const SizedBox(height: HavenSpacing.sm + 2),
            Row(
              children: [
                _StatusPill(
                  count: activeWarranties,
                  label: 'Active',
                  dot: HavenColors.active,
                  onTap: onStatusTap == null
                      ? null
                      : () => onStatusTap!('active'),
                ),
                _onGradientDivider(),
                _StatusPill(
                  count: expiringWarranties,
                  label: 'Expiring',
                  dot: HavenColors.expiring,
                  onTap: onStatusTap == null
                      ? null
                      : () => onStatusTap!('expiring'),
                ),
                _onGradientDivider(),
                _StatusPill(
                  count: expiredWarranties,
                  label: 'Expired',
                  dot: HavenColors.expired,
                  onTap: onStatusTap == null
                      ? null
                      : () => onStatusTap!('expired'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _onGradientDivider() => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: HavenSpacing.xs),
        color: _onGradient(0.18),
      );

  /// `$12,800` style — exact dollars with thousands separators, no cents,
  /// no K/M abbreviation (the hero deserves the full figure). Falls back
  /// to compact form above ~$1M so it doesn't overflow.
  static String _compactDollars(num n) {
    final v = n.round();
    if (v.abs() >= 1000000) {
      return '${(v / 1000000).toStringAsFixed(1)}M';
    }
    final s = v.abs().toString();
    final buf = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// One cell of the active/expiring/expired pill row on the hero.
class _StatusPill extends StatelessWidget {
  final int count;
  final String label;
  final Color dot;
  final VoidCallback? onTap;

  const _StatusPill({
    required this.count,
    required this.label,
    required this.dot,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: HavenText.titleLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: HavenText.caption
                .copyWith(color: Colors.white.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );

    return Expanded(
      child: onTap == null
          ? body
          : Semantics(
              button: true,
              label: '$count $label warranties',
              excludeSemantics: true,
              child: Material(
                type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(HavenRadius.button),
                child: InkWell(
                  onTap: () {
                    HavenHaptics.tap();
                    onTap!();
                  },
                  borderRadius: BorderRadius.circular(HavenRadius.button),
                  splashColor: Colors.white.withValues(alpha: 0.14),
                  highlightColor: Colors.white.withValues(alpha: 0.06),
                  child: body,
                ),
              ),
            ),
    );
  }
}
