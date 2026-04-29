import '_unknown_enum_log.dart';
import 'enums.dart';

/// A realtor / builder / contractor partner profile.
///
/// Mirrors the `partners` table on the API (migrations 002, 017, 041). The
/// Phase 1 dart_packages agent introduced PartnerGift + PartnerCommission;
/// this model rounds out the parent record (Ch08-Partner-D050..D061).
///
/// `@internal`-by-convention: only the partner-dashboard and admin views
/// need this model directly — the consumer mobile app reads `is_partner`
/// off [User] instead. We export it from the shared_models barrel so
/// admin tooling can deserialize partner rows without re-implementing the
/// JSON envelope.
class Partner {
  /// UUID primary key.
  final String id;

  /// FK to `users.id` — the user account owning the partner row.
  final String userId;

  final PartnerType partnerType;
  final String? companyName;
  final String? phone;

  /// Public website URL (Ch08-Partner-D051).
  final String? website;

  /// Hex brand color, e.g. `#FF5733`. The API enforces the regex via the
  /// `chk_partners_brand_color_hex` CHECK (mig 041) so any non-null value
  /// here is guaranteed well-formed (Ch08-Partner-D052).
  final String? brandColor;

  /// Partner logo URL (Ch08-Partner-D053).
  final String? logoUrl;

  final PartnerSubscriptionTier subscriptionTier;

  /// Default custom message inlined in gift activation emails
  /// (Ch08-Partner-D055).
  final String? defaultMessage;

  /// Default premium-months value pre-filled on the Create Gift form
  /// (Ch08-Partner-D056). Bound to 1..12 by the partner Joi schema.
  final int defaultPremiumMonths;

  /// True iff the partner has finished Stripe Connect onboarding
  /// (Ch08-Partner-D057). The Stripe account id itself is stripped from
  /// API responses post-Phase 4 to avoid leaking it through the dashboard
  /// JSON; presence is surfaced as a boolean only.
  final bool stripeOnboarded;

  /// Three-state approval status (mig 071 / Ch10-W054). This is the source
  /// of truth — `isActive` is kept in sync for legacy callers but new code
  /// should branch on [status] so it can distinguish "pending review" from
  /// "explicitly rejected."
  final PartnerStatus status;

  /// Legacy approval flag — true iff [status] is [PartnerStatus.active].
  /// Retained for backwards compatibility with screens that haven't migrated
  /// to [status] yet (Ch08-Partner-D058 — mig 017 changed the DB default).
  final bool isActive;

  /// Identity-verified flag (Ch08-Partner-D059).
  final bool isVerified;

  /// Optional list of zip codes / city names this partner services
  /// (Ch08-Partner-D060).
  final List<String> serviceAreas;

  /// State-issued license number, when applicable (Ch08-Partner-D061).
  final String? licenseNumber;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Partner({
    required this.id,
    required this.userId,
    required this.partnerType,
    this.companyName,
    this.phone,
    this.website,
    this.brandColor,
    this.logoUrl,
    this.subscriptionTier = PartnerSubscriptionTier.basic,
    this.defaultMessage,
    this.defaultPremiumMonths = 6,
    this.stripeOnboarded = false,
    this.status = PartnerStatus.pending,
    this.isActive = false,
    this.isVerified = false,
    this.serviceAreas = const [],
    this.licenseNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Partner.fromJson(Map<String, dynamic> json) {
    return Partner(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      partnerType: PartnerType.fromJson(
        json['partner_type'] as String? ?? 'other',
      ),
      companyName: json['company_name'] as String?,
      phone: json['phone'] as String?,
      website: json['website'] as String?,
      brandColor: json['brand_color'] as String?,
      logoUrl: json['logo_url'] as String?,
      subscriptionTier: PartnerSubscriptionTier.fromJson(
        json['subscription_tier'] as String? ?? 'basic',
      ),
      defaultMessage: json['default_message'] as String?,
      defaultPremiumMonths:
          (json['default_premium_months'] as num?)?.toInt() ?? 6,
      stripeOnboarded: json['stripe_onboarded'] as bool? ??
          (json['has_stripe_account'] as bool? ?? false),
      status: PartnerStatus.fromJson(json['status'] as String? ?? 'pending'),
      isActive: json['is_active'] as bool? ?? false,
      isVerified: json['is_verified'] as bool? ?? false,
      serviceAreas: json['service_areas'] is List
          ? (json['service_areas'] as List)
              .map((e) => e as String)
              .toList(growable: false)
          : const [],
      licenseNumber: json['license_number'] as String?,
      // 4.1: server-stamped timestamps fall back instead of crashing.
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'partner_type': partnerType.toJson(),
        'company_name': companyName,
        'phone': phone,
        'website': website,
        'brand_color': brandColor,
        'logo_url': logoUrl,
        'subscription_tier': subscriptionTier.toJson(),
        'default_message': defaultMessage,
        'default_premium_months': defaultPremiumMonths,
        'stripe_onboarded': stripeOnboarded,
        'status': status.toJson(),
        'is_active': isActive,
        'is_verified': isVerified,
        'service_areas': serviceAreas,
        'license_number': licenseNumber,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Partner copyWith({
    String? id,
    String? userId,
    PartnerType? partnerType,
    String? companyName,
    bool clearCompanyName = false,
    String? phone,
    bool clearPhone = false,
    String? website,
    bool clearWebsite = false,
    String? brandColor,
    bool clearBrandColor = false,
    String? logoUrl,
    bool clearLogoUrl = false,
    PartnerSubscriptionTier? subscriptionTier,
    String? defaultMessage,
    bool clearDefaultMessage = false,
    int? defaultPremiumMonths,
    bool? stripeOnboarded,
    PartnerStatus? status,
    bool? isActive,
    bool? isVerified,
    List<String>? serviceAreas,
    String? licenseNumber,
    bool clearLicenseNumber = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Partner(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      partnerType: partnerType ?? this.partnerType,
      companyName: clearCompanyName ? null : (companyName ?? this.companyName),
      phone: clearPhone ? null : (phone ?? this.phone),
      website: clearWebsite ? null : (website ?? this.website),
      brandColor: clearBrandColor ? null : (brandColor ?? this.brandColor),
      logoUrl: clearLogoUrl ? null : (logoUrl ?? this.logoUrl),
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      defaultMessage:
          clearDefaultMessage ? null : (defaultMessage ?? this.defaultMessage),
      defaultPremiumMonths: defaultPremiumMonths ?? this.defaultPremiumMonths,
      stripeOnboarded: stripeOnboarded ?? this.stripeOnboarded,
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      serviceAreas: serviceAreas ?? this.serviceAreas,
      licenseNumber:
          clearLicenseNumber ? null : (licenseNumber ?? this.licenseNumber),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Partner(id: $id, type: ${partnerType.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Partner && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Mirrors the `partner_status` Postgres enum (mig 071 / Ch10-W054):
/// `pending | active | rejected`.
enum PartnerStatus {
  pending,
  active,
  rejected;

  static const Map<String, PartnerStatus> _byName = {
    'pending': PartnerStatus.pending,
    'active': PartnerStatus.active,
    'rejected': PartnerStatus.rejected,
  };

  factory PartnerStatus.fromJson(String value) {
    final mapped = _byName[value];
    if (mapped != null) return mapped;
    logUnknownEnumValue(
      enumName: 'PartnerStatus',
      unknownValue: value,
      fallback: 'pending',
    );
    return PartnerStatus.pending;
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        PartnerStatus.pending => 'Pending',
        PartnerStatus.active => 'Active',
        PartnerStatus.rejected => 'Rejected',
      };
}

/// Mirrors the `partner_tier` Postgres enum (basic / premium / platinum).
enum PartnerSubscriptionTier {
  basic,
  premium,
  platinum;

  static const Map<String, PartnerSubscriptionTier> _byName = {
    'basic': PartnerSubscriptionTier.basic,
    'premium': PartnerSubscriptionTier.premium,
    'platinum': PartnerSubscriptionTier.platinum,
  };

  factory PartnerSubscriptionTier.fromJson(String value) {
    return _byName[value] ?? PartnerSubscriptionTier.basic;
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        PartnerSubscriptionTier.basic => 'Basic',
        PartnerSubscriptionTier.premium => 'Premium',
        PartnerSubscriptionTier.platinum => 'Platinum',
      };
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
