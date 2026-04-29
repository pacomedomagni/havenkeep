import 'enums.dart';

/// User profile with app-specific fields.
///
/// Mirrors the `users` table on the API after the soft-delete migrations
/// (016) added [deletedAt] / [deletionScheduledFor]. The API never returns
/// `stripe_customer_id` to the client (Ch08-User-D005); if it shows up here
/// we treat it as a server bug and ignore it on read.
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
  final bool emailVerified;
  final String? appleUserId;
  final bool isAdmin;

  /// True when the API returned `is_partner: true`. Computed server-side
  /// from `partners.is_active = TRUE` (see `routes/users.ts`). The mobile
  /// client must NOT fabricate this value (Ch08-User-D002).
  final bool isPartner;

  /// Soft-delete marker. Non-null inside the 30-day cooling-off window
  /// (Ch08-User-D003).
  final DateTime? deletedAt;

  /// Hard-delete deadline. When [deletedAt] is set this points 30 days
  /// later (Ch08-User-D004).
  final DateTime? deletionScheduledFor;

  /// True when the user has requested an email change but the verification
  /// link in the new mailbox hasn't been clicked yet. Drives the
  /// "verification pending" badge on the profile screen.
  final bool emailChangePending;

  /// The new email address awaiting verification. Only non-null when
  /// [emailChangePending] is true.
  final String? emailChangeTarget;

  final DateTime createdAt;
  final DateTime updatedAt;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    required this.authProvider,
    this.plan = UserPlan.free,
    this.planExpiresAt,
    this.referredBy,
    this.referralCode,
    this.emailVerified = false,
    this.appleUserId,
    this.isAdmin = false,
    this.isPartner = false,
    this.deletedAt,
    this.deletionScheduledFor,
    this.emailChangePending = false,
    this.emailChangeTarget,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      // Ch08-User-D001: no silent default. The API always sets
      // auth_provider on insert; if it's missing we fail loud rather than
      // pretend the user is an email/password account.
      authProvider: AuthProvider.fromJson(json['auth_provider'] as String),
      plan: json['plan'] != null
          ? UserPlan.fromJson(json['plan'] as String)
          : UserPlan.free,
      planExpiresAt: _parseDate(json['plan_expires_at']),
      referredBy: json['referred_by'] as String?,
      referralCode: json['referral_code'] as String?,
      emailVerified: json['email_verified'] as bool? ?? false,
      appleUserId: json['apple_user_id'] as String?,
      isAdmin: json['is_admin'] as bool? ?? false,
      isPartner: json['is_partner'] as bool? ?? false,
      deletedAt: _parseDate(json['deleted_at']),
      deletionScheduledFor: _parseDate(json['deletion_scheduled_for']),
      emailChangePending: json['email_change_pending'] as bool? ?? false,
      emailChangeTarget: json['email_change_target'] as String?,
      // 4.1: server-stamped timestamps fall back instead of crashing.
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
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
      'email_verified': emailVerified,
      'apple_user_id': appleUserId,
      'is_admin': isAdmin,
      'is_partner': isPartner,
      // Only emit timestamps when set so a hydrated round-trip is symmetric
      // (Ch08-User-D003 / D004: client never fabricates these).
      if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
      if (deletionScheduledFor != null)
        'deletion_scheduled_for': deletionScheduledFor!.toIso8601String(),
      if (emailChangePending) 'email_change_pending': true,
      if (emailChangeTarget != null) 'email_change_target': emailChangeTarget,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// True when the account is in the 30-day soft-delete cooling-off window.
  bool get isPendingDeletion => deletedAt != null;

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
    bool? emailVerified,
    String? appleUserId,
    bool clearAppleUserId = false,
    bool? isAdmin,
    bool? isPartner,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? deletionScheduledFor,
    bool clearDeletionScheduledFor = false,
    bool? emailChangePending,
    String? emailChangeTarget,
    bool clearEmailChangeTarget = false,
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
      emailVerified: emailVerified ?? this.emailVerified,
      appleUserId: clearAppleUserId ? null : (appleUserId ?? this.appleUserId),
      isAdmin: isAdmin ?? this.isAdmin,
      isPartner: isPartner ?? this.isPartner,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      deletionScheduledFor: clearDeletionScheduledFor
          ? null
          : (deletionScheduledFor ?? this.deletionScheduledFor),
      emailChangePending: emailChangePending ?? this.emailChangePending,
      emailChangeTarget: clearEmailChangeTarget
          ? null
          : (emailChangeTarget ?? this.emailChangeTarget),
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

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
