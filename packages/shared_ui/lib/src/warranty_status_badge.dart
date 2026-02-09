import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';
import 'theme.dart';

/// A status indicator badge for warranty items.
///
/// Shows a colored dot paired with descriptive text reflecting the current
/// warranty status. In [compact] mode only the dot and short label are shown.
/// In full mode, [daysRemaining] is used to build a more descriptive string
/// (e.g., "2 years 3 months left" or "15 days left").
class WarrantyStatusBadge extends StatelessWidget {
  const WarrantyStatusBadge({
    super.key,
    required this.status,
    this.daysRemaining,
    this.compact = false,
  });

  /// The warranty status to display.
  final WarrantyStatus status;

  /// Optional number of days remaining (positive) or days since expiry
  /// (negative) for more detailed text. Ignored in [compact] mode.
  final int? daysRemaining;

  /// If true, shows only the dot and the short [WarrantyStatus.displayLabel].
  final bool compact;

  Color get _statusColor => switch (status) {
        WarrantyStatus.active => HavenColors.active,
        WarrantyStatus.expiring => HavenColors.expiring,
        WarrantyStatus.expired => HavenColors.expired,
      };

  String get _label {
    if (compact) {
      return status.displayLabel;
    }

    switch (status) {
      case WarrantyStatus.active:
        if (daysRemaining != null && daysRemaining! > 0) {
          return _formatDaysAsYearsMonths(daysRemaining!);
        }
        return 'Active';

      case WarrantyStatus.expiring:
        if (daysRemaining != null && daysRemaining! > 0) {
          return '$daysRemaining days left';
        }
        return 'Expiring Soon';

      case WarrantyStatus.expired:
        if (daysRemaining != null && daysRemaining! < 0) {
          return 'Expired ${daysRemaining!.abs()} days ago';
        }
        return 'Expired';
    }
  }

  /// Converts a positive number of days into a human-readable
  /// "X years Y months left" or "X months left" string.
  String _formatDaysAsYearsMonths(int days) {
    final years = days ~/ 365;
    final remainingDays = days % 365;
    final months = remainingDays ~/ 30;

    if (years > 0 && months > 0) {
      return '$years ${years == 1 ? 'year' : 'years'} '
          '$months ${months == 1 ? 'month' : 'months'} left';
    } else if (years > 0) {
      return '$years ${years == 1 ? 'year' : 'years'} left';
    } else if (months > 0) {
      return '$months ${months == 1 ? 'month' : 'months'} left';
    }
    return '$days days left';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _statusColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: HavenSpacing.sm),
        Text(
          _label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _statusColor,
          ),
        ),
      ],
    );
  }
}
