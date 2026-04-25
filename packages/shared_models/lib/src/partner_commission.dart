/// A commission earned by a partner for a [PartnerCommissionType] event
/// (gift purchase, warranty sale, referral).
///
/// Mirrors the `partner_commissions` table on the API after migration 030
/// (`030_commission_clawback_and_transfer.sql`), which added the
/// `reversed` status, the [reversalOfCommissionId] back-pointer for
/// clawback rows, and the CHECK that any `paid` row carries a real Stripe
/// transfer id.
class PartnerCommission {
  /// UUID primary key.
  final String id;

  /// FK to `partners.id`.
  final String partnerId;

  /// What this commission is for.
  final PartnerCommissionType type;

  /// Dollar amount. Positive on the original earning row; negative on a
  /// `reversed` clawback row (CHECK `chk_partner_commissions_reversal_shape`
  /// enforces this).
  final double amount;

  /// Fractional rate the amount was computed at, e.g. `0.15` for 15 %.
  final double commissionRate;

  /// Lifecycle state.
  final PartnerCommissionStatus status;

  /// FK pointer to whichever row this commission was earned from. The
  /// concrete table is named in [referenceType].
  final String? referenceId;

  /// Always one of `partner_gift`, `warranty_purchase`, `subscription` after
  /// migration 070 (Ch08-PartnerCommission-D067 added the CHECK).
  final PartnerCommissionReferenceType? referenceType;

  /// `stripe_connect`, `manual_check`, or `ach` after migration 070
  /// (Ch08-PartnerCommission-D068 added the CHECK).
  final PartnerCommissionPayoutMethod? payoutMethod;

  /// Stripe Transfer id (`tr_...`) once the payout has cleared. NULL until
  /// transfer; required when [status] is `paid`.
  final String? stripeTransferId;

  /// On a `reversed` row, the FK back to the original commission this row
  /// claws back. Required when [status] is `reversed`.
  final String? reversalOfCommissionId;

  final DateTime createdAt;
  final DateTime updatedAt;

  const PartnerCommission({
    required this.id,
    required this.partnerId,
    required this.type,
    required this.amount,
    required this.commissionRate,
    required this.status,
    this.referenceId,
    this.referenceType,
    this.payoutMethod,
    this.stripeTransferId,
    this.reversalOfCommissionId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PartnerCommission.fromJson(Map<String, dynamic> json) {
    return PartnerCommission(
      id: json['id'] as String? ?? '',
      partnerId: json['partner_id'] as String? ?? '',
      type: PartnerCommissionType.fromJson(
        json['type'] as String? ?? 'referral',
      ),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      commissionRate: (json['commission_rate'] as num?)?.toDouble() ?? 0,
      status: PartnerCommissionStatus.fromJson(
        json['status'] as String? ?? 'pending',
      ),
      referenceId: json['reference_id'] as String?,
      referenceType: json['reference_type'] != null
          ? PartnerCommissionReferenceType.fromJson(
              json['reference_type'] as String)
          : null,
      payoutMethod: json['payout_method'] != null
          ? PartnerCommissionPayoutMethod.fromJson(
              json['payout_method'] as String)
          : null,
      stripeTransferId: json['stripe_transfer_id'] as String?,
      reversalOfCommissionId: json['reversal_of_commission_id'] as String?,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'partner_id': partnerId,
        'type': type.toJson(),
        'amount': amount,
        'commission_rate': commissionRate,
        'status': status.toJson(),
        if (referenceId != null) 'reference_id': referenceId,
        if (referenceType != null) 'reference_type': referenceType!.toJson(),
        if (payoutMethod != null) 'payout_method': payoutMethod!.toJson(),
        if (stripeTransferId != null) 'stripe_transfer_id': stripeTransferId,
        if (reversalOfCommissionId != null)
          'reversal_of_commission_id': reversalOfCommissionId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// Mirrors the `commission_type` Postgres enum.
enum PartnerCommissionType {
  gift,
  warranty_sale,
  referral;

  factory PartnerCommissionType.fromJson(String value) {
    return PartnerCommissionType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PartnerCommissionType.referral,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        PartnerCommissionType.gift => 'Gift',
        PartnerCommissionType.warranty_sale => 'Warranty Sale',
        PartnerCommissionType.referral => 'Referral',
      };
}

/// Mirrors the `commission_status` Postgres enum **after** migration 030
/// added the `reversed` value.
enum PartnerCommissionStatus {
  pending,
  approved,
  paid,
  cancelled,
  reversed;

  factory PartnerCommissionStatus.fromJson(String value) {
    return PartnerCommissionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PartnerCommissionStatus.pending,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        PartnerCommissionStatus.pending => 'Pending',
        PartnerCommissionStatus.approved => 'Approved',
        PartnerCommissionStatus.paid => 'Paid',
        PartnerCommissionStatus.cancelled => 'Cancelled',
        PartnerCommissionStatus.reversed => 'Reversed',
      };
}

/// Mirrors the `partner_commissions.reference_type` CHECK enum after
/// migration 070 (Ch08-PartnerCommission-D067).
enum PartnerCommissionReferenceType {
  partner_gift,
  warranty_purchase,
  subscription;

  static const Map<String, PartnerCommissionReferenceType> _byName = {
    'partner_gift': PartnerCommissionReferenceType.partner_gift,
    'warranty_purchase': PartnerCommissionReferenceType.warranty_purchase,
    'subscription': PartnerCommissionReferenceType.subscription,
  };

  factory PartnerCommissionReferenceType.fromJson(String value) {
    return _byName[value] ?? PartnerCommissionReferenceType.partner_gift;
  }

  String toJson() => name;
}

/// Mirrors the `partner_commissions.payout_method` CHECK enum after
/// migration 070 (Ch08-PartnerCommission-D068).
enum PartnerCommissionPayoutMethod {
  stripe_connect,
  manual_check,
  ach;

  static const Map<String, PartnerCommissionPayoutMethod> _byName = {
    'stripe_connect': PartnerCommissionPayoutMethod.stripe_connect,
    'manual_check': PartnerCommissionPayoutMethod.manual_check,
    'ach': PartnerCommissionPayoutMethod.ach,
  };

  factory PartnerCommissionPayoutMethod.fromJson(String value) {
    return _byName[value] ?? PartnerCommissionPayoutMethod.stripe_connect;
  }

  String toJson() => name;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
