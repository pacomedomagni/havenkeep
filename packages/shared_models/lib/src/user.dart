import 'enums.dart';

/// User profile with app-specific fields.
class User {
  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final AuthProvider authProvider;
  final UserPlan plan;
  final DateTime? planExpiresAt;
  final String? referredBy;
  final String? referralCode;
  final bool isAdmin;
  final bool isPartner;
  final DateTime createdAt;
  final DateTime updatedAt;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.authProvider = AuthProvider.email,
    this.plan = UserPlan.free,
    this.planExpiresAt,
    this.referredBy,
    this.referralCode,
    this.isAdmin = false,
    this.isPartner = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      authProvider: AuthProvider.fromJson(json['auth_provider'] as String),
      plan: json['plan'] != null ? UserPlan.fromJson(json['plan'] as String) : UserPlan.free,
      planExpiresAt: json['plan_expires_at'] != null
          ? DateTime.parse(json['plan_expires_at'] as String)
          : null,
      referredBy: json['referred_by'] as String?,
      referralCode: json['referral_code'] as String?,
      isAdmin: json['is_admin'] as bool? ?? false,
      isPartner: json['is_partner'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'auth_provider': authProvider.toJson(),
      'plan': plan.toJson(),
      'plan_expires_at': planExpiresAt?.toIso8601String(),
      'referred_by': referredBy,
      'referral_code': referralCode,
      'is_admin': isAdmin,
      'is_partner': isPartner,
    };
  }

  User copyWith({
    String? id,
    String? email,
    String? fullName,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    AuthProvider? authProvider,
    UserPlan? plan,
    DateTime? planExpiresAt,
    bool clearPlanExpiresAt = false,
    String? referredBy,
    bool clearReferredBy = false,
    String? referralCode,
    bool clearReferralCode = false,
    bool? isAdmin,
    bool? isPartner,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      authProvider: authProvider ?? this.authProvider,
      plan: plan ?? this.plan,
      planExpiresAt: clearPlanExpiresAt
          ? null
          : (planExpiresAt ?? this.planExpiresAt),
      referredBy: clearReferredBy ? null : (referredBy ?? this.referredBy),
      referralCode:
          clearReferralCode ? null : (referralCode ?? this.referralCode),
      isAdmin: isAdmin ?? this.isAdmin,
      isPartner: isPartner ?? this.isPartner,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'User(id: $id, email: $email, fullName: $fullName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is User && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
