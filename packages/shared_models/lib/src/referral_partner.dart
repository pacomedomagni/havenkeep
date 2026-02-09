import 'enums.dart';

/// A referral partner (realtor, builder) who refers users to HavenKeep.
class ReferralPartner {
  final String id;
  final String email;
  final String fullName;
  final String? companyName;
  final String? phone;
  final String? avatarUrl;
  final PartnerType partnerType;
  final String referralCode;
  final String? stripeAccountId;
  final bool isActive;
  final DateTime createdAt;

  const ReferralPartner({
    required this.id,
    required this.email,
    required this.fullName,
    this.companyName,
    this.phone,
    this.avatarUrl,
    this.partnerType = PartnerType.realtor,
    required this.referralCode,
    this.stripeAccountId,
    this.isActive = true,
    required this.createdAt,
  });

  factory ReferralPartner.fromJson(Map<String, dynamic> json) {
    return ReferralPartner(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      companyName: json['company_name'] as String?,
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      partnerType: PartnerType.fromJson(json['partner_type'] as String),
      referralCode: json['referral_code'] as String,
      stripeAccountId: json['stripe_account_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'company_name': companyName,
      'phone': phone,
      'avatar_url': avatarUrl,
      'partner_type': partnerType.toJson(),
      'referral_code': referralCode,
      'stripe_account_id': stripeAccountId,
      'is_active': isActive,
    };
  }

  /// Display name for the partner (includes company if available).
  String get displayName =>
      companyName != null ? '$fullName ($companyName)' : fullName;

  ReferralPartner copyWith({
    String? id,
    String? email,
    String? fullName,
    String? companyName,
    bool clearCompanyName = false,
    String? phone,
    bool clearPhone = false,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    PartnerType? partnerType,
    String? referralCode,
    String? stripeAccountId,
    bool clearStripeAccountId = false,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return ReferralPartner(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      companyName:
          clearCompanyName ? null : (companyName ?? this.companyName),
      phone: clearPhone ? null : (phone ?? this.phone),
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      partnerType: partnerType ?? this.partnerType,
      referralCode: referralCode ?? this.referralCode,
      stripeAccountId: clearStripeAccountId
          ? null
          : (stripeAccountId ?? this.stripeAccountId),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'ReferralPartner(id: $id, fullName: $fullName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ReferralPartner && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
