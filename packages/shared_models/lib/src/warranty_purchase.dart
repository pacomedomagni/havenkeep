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
      id: json['id'] as String,
      itemId: json['item_id'] as String,
      userId: json['user_id'] as String,
      provider: json['provider'] as String,
      planName: json['plan_name'] as String,
      externalPolicyId: json['external_policy_id'] as String?,
      durationMonths: (json['duration_months'] as num).toInt(),
      startsAt: DateTime.tryParse(json['starts_at'] as String? ?? '') ?? DateTime.now(),
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ?? DateTime.now(),
      coverageDetails: json['coverage_details'] as Map<String, dynamic>?,
      price: (json['price'] as num).toDouble(),
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
      purchaseDate: DateTime.tryParse(json['purchase_date'] as String? ?? '') ?? DateTime.now(),
      stripePaymentIntentId: json['stripe_payment_intent_id'] as String?,
      status: WarrantyPurchaseStatus.fromJson(json['status'] as String? ?? 'active'),
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.tryParse(json['cancelled_at'] as String)
          : null,
      cancellationReason: json['cancellation_reason'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      itemName: json['item_name'] as String?,
      itemCategory: json['item_category'] as String?,
      itemBrand: json['item_brand'] as String?,
      itemModelNumber: json['item_model_number'] as String?,
    );
  }

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
      };
}

enum WarrantyPurchaseStatus {
  active,
  expired,
  cancelled,
  pending,
  claimed;

  factory WarrantyPurchaseStatus.fromJson(String value) {
    return WarrantyPurchaseStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => WarrantyPurchaseStatus.active,
    );
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
