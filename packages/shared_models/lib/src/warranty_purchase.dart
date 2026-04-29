/// Represents a purchased/extended warranty for an item.
class WarrantyPurchase {
  final String id;
  final String itemId;
  final String userId;
  final String provider;
  final String planName;
  final String? externalPolicyId;
  final int durationMonths;
  final DateTime startsAt;
  final DateTime expiresAt;
  final Map<String, dynamic>? coverageDetails;
  final double price;
  final double deductible;
  final double? claimLimit;
  final double? commissionAmount;
  final double? commissionRate;
  final DateTime purchaseDate;
  final String? stripePaymentIntentId;
  final WarrantyPurchaseStatus status;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined item fields
  final String? itemName;
  final String? itemCategory;
  final String? itemBrand;
  final String? itemModelNumber;

  const WarrantyPurchase({
    required this.id,
    required this.itemId,
    required this.userId,
    required this.provider,
    required this.planName,
    this.externalPolicyId,
    required this.durationMonths,
    required this.startsAt,
    required this.expiresAt,
    this.coverageDetails,
    required this.price,
    required this.deductible,
    this.claimLimit,
    this.commissionAmount,
    this.commissionRate,
    required this.purchaseDate,
    this.stripePaymentIntentId,
    required this.status,
    this.cancelledAt,
    this.cancellationReason,
    required this.createdAt,
    required this.updatedAt,
    this.itemName,
    this.itemCategory,
    this.itemBrand,
    this.itemModelNumber,
  });

  factory WarrantyPurchase.fromJson(Map<String, dynamic> json) {
    return WarrantyPurchase(
      id: json['id'] as String? ?? '',
      itemId: json['item_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      planName: json['plan_name'] as String? ?? '',
      externalPolicyId: json['external_policy_id'] as String?,
      durationMonths: (json['duration_months'] as num?)?.toInt() ?? 0,
      // Ch08-WarrantyPurchase-D028: no DateTime.now() fallbacks. starts_at,
      // expires_at, purchase_date are NOT NULL on the API; if a row arrives
      // without one, that's a server bug we want loud.
      startsAt: _parseDate(json['starts_at'])!,
      expiresAt: _parseDate(json['expires_at'])!,
      coverageDetails: json['coverage_details'] is Map
          ? json['coverage_details'] as Map<String, dynamic>?
          : null,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      deductible: (json['deductible'] as num?)?.toDouble() ?? 0,
      claimLimit: json['claim_limit'] != null
          ? (json['claim_limit'] as num).toDouble()
          : null,
      commissionAmount: json['commission_amount'] != null
          ? (json['commission_amount'] as num).toDouble()
          : null,
      commissionRate: json['commission_rate'] != null
          ? (json['commission_rate'] as num).toDouble()
          : null,
      purchaseDate: _parseDate(json['purchase_date'])!,
      stripePaymentIntentId: json['stripe_payment_intent_id'] as String?,
      status: WarrantyPurchaseStatus.fromJson(
        json['status'] as String? ?? 'active',
      ),
      cancelledAt: _parseDate(json['cancelled_at']),
      cancellationReason: json['cancellation_reason'] as String?,
      // 4.1: server-stamped timestamps fall back instead of crashing.
      // starts_at / expires_at / purchase_date keep `!` (D028 above —
      // required-by-contract).
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
      itemName: json['item_name'] as String?,
      itemCategory: json['item_category'] as String?,
      itemBrand: json['item_brand'] as String?,
      itemModelNumber: json['item_model_number'] as String?,
    );
  }

  /// Full JSON for reads.
  Map<String, dynamic> toJson() => {
        'id': id,
        'item_id': itemId,
        'user_id': userId,
        'provider': provider,
        'plan_name': planName,
        if (externalPolicyId != null) 'external_policy_id': externalPolicyId,
        'duration_months': durationMonths,
        'starts_at': startsAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        if (coverageDetails != null) 'coverage_details': coverageDetails,
        'price': price,
        'deductible': deductible,
        if (claimLimit != null) 'claim_limit': claimLimit,
        if (commissionAmount != null) 'commission_amount': commissionAmount,
        if (commissionRate != null) 'commission_rate': commissionRate,
        'purchase_date': purchaseDate.toIso8601String(),
        if (stripePaymentIntentId != null)
          'stripe_payment_intent_id': stripePaymentIntentId,
        'status': status.toJson(),
        if (cancelledAt != null) 'cancelled_at': cancelledAt!.toIso8601String(),
        if (cancellationReason != null) 'cancellation_reason': cancellationReason,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// Creates the JSON body for a POST request.
  ///
  /// Note: [expiresAt] is intentionally omitted. The server calculates it
  /// from [startsAt] + [durationMonths] to ensure consistent date arithmetic.
  Map<String, dynamic> toCreateJson() => {
        'item_id': itemId,
        'provider': provider,
        'plan_name': planName,
        if (externalPolicyId != null) 'external_policy_id': externalPolicyId,
        'duration_months': durationMonths,
        'starts_at': startsAt.toIso8601String(),
        if (coverageDetails != null) 'coverage_details': coverageDetails,
        'price': price,
        'deductible': deductible,
        if (claimLimit != null) 'claim_limit': claimLimit,
        if (commissionAmount != null) 'commission_amount': commissionAmount,
        if (commissionRate != null) 'commission_rate': commissionRate,
        if (stripePaymentIntentId != null)
          'stripe_payment_intent_id': stripePaymentIntentId,
        'status': status.toJson(),
      };
}

enum WarrantyPurchaseStatus {
  active,
  expired,
  cancelled,
  pending,
  claimed;

  static const Map<String, WarrantyPurchaseStatus> _byName = {
    'active': WarrantyPurchaseStatus.active,
    'expired': WarrantyPurchaseStatus.expired,
    'cancelled': WarrantyPurchaseStatus.cancelled,
    'pending': WarrantyPurchaseStatus.pending,
    'claimed': WarrantyPurchaseStatus.claimed,
  };

  factory WarrantyPurchaseStatus.fromJson(String value) {
    return _byName[value] ?? WarrantyPurchaseStatus.active;
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        WarrantyPurchaseStatus.active => 'Active',
        WarrantyPurchaseStatus.expired => 'Expired',
        WarrantyPurchaseStatus.cancelled => 'Cancelled',
        WarrantyPurchaseStatus.pending => 'Pending',
        WarrantyPurchaseStatus.claimed => 'Claimed',
      };
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
