import 'enums.dart';

/// A tracked affiliate conversion (warranty purchase, repair referral, etc.).
class AffiliateConversion {
  final String id;
  final String userId;
  final String? itemId;
  final String? partnerId;
  final ConversionType type;
  final String provider;
  final double revenue;
  final double commission;
  final double partnerCommission;
  final ConversionStatus status;
  final DateTime createdAt;

  const AffiliateConversion({
    required this.id,
    required this.userId,
    this.itemId,
    this.partnerId,
    required this.type,
    required this.provider,
    this.revenue = 0.0,
    this.commission = 0.0,
    this.partnerCommission = 0.0,
    this.status = ConversionStatus.pending,
    required this.createdAt,
  });

  factory AffiliateConversion.fromJson(Map<String, dynamic> json) {
    return AffiliateConversion(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      itemId: json['item_id'] as String?,
      partnerId: json['partner_id'] as String?,
      type: ConversionType.fromJson(json['type'] as String),
      provider: json['provider'] as String,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
      commission: (json['commission'] as num?)?.toDouble() ?? 0.0,
      partnerCommission:
          (json['partner_commission'] as num?)?.toDouble() ?? 0.0,
      status: ConversionStatus.fromJson(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'item_id': itemId,
      'partner_id': partnerId,
      'type': type.toJson(),
      'provider': provider,
      'revenue': revenue,
      'commission': commission,
      'partner_commission': partnerCommission,
      'status': status.toJson(),
    };
  }

  AffiliateConversion copyWith({
    String? id,
    String? userId,
    String? itemId,
    bool clearItemId = false,
    String? partnerId,
    bool clearPartnerId = false,
    ConversionType? type,
    String? provider,
    double? revenue,
    double? commission,
    double? partnerCommission,
    ConversionStatus? status,
    DateTime? createdAt,
  }) {
    return AffiliateConversion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      itemId: clearItemId ? null : (itemId ?? this.itemId),
      partnerId: clearPartnerId ? null : (partnerId ?? this.partnerId),
      type: type ?? this.type,
      provider: provider ?? this.provider,
      revenue: revenue ?? this.revenue,
      commission: commission ?? this.commission,
      partnerCommission: partnerCommission ?? this.partnerCommission,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'AffiliateConversion(id: $id, type: ${type.name}, status: ${status.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AffiliateConversion && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
