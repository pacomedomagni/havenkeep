import '_unknown_enum_log.dart';

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
  final DateTime purchaseDate;
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
    required this.purchaseDate,
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
      purchaseDate: _parseDate(json['purchase_date'])!,
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
        'purchase_date': purchaseDate.toIso8601String(),
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
        'status': status.toJson(),
      };
}

enum WarrantyPurchaseStatus {
  active,
  expired,
  cancelled,
  // C0-31: API mig 098 added `cancelling` as the transient state in
  // the three-phase cancel flow (status flips to `cancelling` between
  // the DB reservation and the Stripe refund). Mobile must surface a
  // distinct state — falling back to `active` left a Cancel button
  // visible on rows already mid-cancel, leading to a second
  // /cancel request and duplicate refund attempts.
  cancelling,
  pending,
  claimed;

  static const Map<String, WarrantyPurchaseStatus> _byName = {
    'active': WarrantyPurchaseStatus.active,
    'expired': WarrantyPurchaseStatus.expired,
    'cancelled': WarrantyPurchaseStatus.cancelled,
    'cancelling': WarrantyPurchaseStatus.cancelling,
    'pending': WarrantyPurchaseStatus.pending,
    'claimed': WarrantyPurchaseStatus.claimed,
  };

  factory WarrantyPurchaseStatus.fromJson(String value) {
    final mapped = _byName[value];
    if (mapped != null) return mapped;
    // Unknown value: log via the shared funnel (Ch08-D018) so an enum
    // drift between server and client surfaces in platform logs, then
    // coerce to `active` so the UI keeps rendering.
    logUnknownEnumValue(
      enumName: 'WarrantyPurchaseStatus',
      unknownValue: value,
      fallback: 'active',
    );
    return WarrantyPurchaseStatus.active;
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        WarrantyPurchaseStatus.active => 'Active',
        WarrantyPurchaseStatus.expired => 'Expired',
        WarrantyPurchaseStatus.cancelled => 'Cancelled',
        WarrantyPurchaseStatus.cancelling => 'Cancelling…',
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
