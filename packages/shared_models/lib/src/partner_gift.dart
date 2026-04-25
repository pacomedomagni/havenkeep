/// A "closing gift" issued by a partner (realtor / builder / etc.) to a
/// homebuyer. The partner pays for a fixed number of premium months that
/// the homebuyer redeems via the activation flow.
///
/// Mirrors the `partner_gifts` table on the API. Field names use snake_case
/// to match the JSON envelope returned by `partners.service.ts`.
class PartnerGift {
  /// UUID primary key.
  final String id;

  /// FK to `partners.id`.
  final String partnerId;

  /// Lower-cased recipient email. The activation flow refuses to redeem
  /// against any other address.
  final String homebuyerEmail;

  /// Display name shown in the activation email + welcome screen.
  final String homebuyerName;

  /// Months of premium granted on activation. Stacks on top of any existing
  /// future expiry on the user (server-side logic, see migration 002).
  final int premiumMonths;

  /// Lifecycle state.
  final PartnerGiftStatus status;

  /// Stripe PaymentIntent id (`pi_...`). Null while status is
  /// `pending_payment`; set once the partner's card is charged.
  final String? stripeChargeId;

  /// SHA-256 hex of the activation code. The plaintext code is only ever
  /// embedded in the activation email; the DB only retains the hash so a
  /// DB compromise can't be replayed against the activation endpoint.
  final String? activationCodeHash;

  /// True once the homebuyer redeemed the gift.
  final bool isActivated;

  /// When the gift was redeemed (UTC). Null until activation.
  final DateTime? activatedAt;

  /// FK to the `users.id` row that the gift activated. Null until
  /// activation.
  final String? activatedUserId;

  /// Hard expiry — after this point the gift is dead even if unredeemed.
  /// Computed server-side as `created_at + premium_months` so a 12-month
  /// gift can't be redeemed 11 months later for a fresh 12 months.
  final DateTime? expiresAt;

  /// Amount the partner was charged in dollars (e.g. `99.00`). The Stripe
  /// charge runs in cents, but we surface dollars on the wire to match the
  /// admin dashboard.
  final double amountCharged;

  final DateTime createdAt;
  final DateTime updatedAt;

  const PartnerGift({
    required this.id,
    required this.partnerId,
    required this.homebuyerEmail,
    required this.homebuyerName,
    required this.premiumMonths,
    required this.status,
    this.stripeChargeId,
    this.activationCodeHash,
    required this.isActivated,
    this.activatedAt,
    this.activatedUserId,
    this.expiresAt,
    required this.amountCharged,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PartnerGift.fromJson(Map<String, dynamic> json) {
    return PartnerGift(
      id: json['id'] as String? ?? '',
      partnerId: json['partner_id'] as String? ?? '',
      homebuyerEmail: json['homebuyer_email'] as String? ?? '',
      homebuyerName: json['homebuyer_name'] as String? ?? '',
      premiumMonths: (json['premium_months'] as num?)?.toInt() ?? 0,
      status: PartnerGiftStatus.fromJson(
        json['status'] as String? ?? 'created',
      ),
      stripeChargeId: json['stripe_charge_id'] as String?,
      activationCodeHash: json['activation_code_hash'] as String?,
      isActivated: json['is_activated'] as bool? ?? false,
      activatedAt: _parseDate(json['activated_at']),
      activatedUserId: json['activated_user_id'] as String?,
      expiresAt: _parseDate(json['expires_at']),
      amountCharged: (json['amount_charged'] as num?)?.toDouble() ?? 0,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'partner_id': partnerId,
        'homebuyer_email': homebuyerEmail,
        'homebuyer_name': homebuyerName,
        'premium_months': premiumMonths,
        'status': status.toJson(),
        if (stripeChargeId != null) 'stripe_charge_id': stripeChargeId,
        if (activationCodeHash != null)
          'activation_code_hash': activationCodeHash,
        'is_activated': isActivated,
        if (activatedAt != null) 'activated_at': activatedAt!.toIso8601String(),
        if (activatedUserId != null) 'activated_user_id': activatedUserId,
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
        'amount_charged': amountCharged,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// Lifecycle states for [PartnerGift]. Mirrors the `gift_status` Postgres
/// enum (see `apps/api/src/db/migrations/002_enhanced_features.sql`).
enum PartnerGiftStatus {
  /// Row inserted, Stripe charge not yet attempted.
  pending_payment,

  /// Stripe charge failed and the gift is dead.
  payment_failed,

  /// Charged successfully but activation email not yet sent.
  created,

  /// Activation email delivered.
  sent,

  /// Homebuyer redeemed the gift.
  activated,

  /// Past `expires_at` without activation.
  expired;

  factory PartnerGiftStatus.fromJson(String value) {
    return PartnerGiftStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PartnerGiftStatus.created,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        PartnerGiftStatus.pending_payment => 'Pending Payment',
        PartnerGiftStatus.payment_failed => 'Payment Failed',
        PartnerGiftStatus.created => 'Created',
        PartnerGiftStatus.sent => 'Sent',
        PartnerGiftStatus.activated => 'Activated',
        PartnerGiftStatus.expired => 'Expired',
      };
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
