import 'enums.dart';

/// A referral record linking a partner to a user they referred.
class Referral {
  final String id;
  final String partnerId;
  final String userId;
  final ReferralSource source;
  final DateTime createdAt;

  const Referral({
    required this.id,
    required this.partnerId,
    required this.userId,
    this.source = ReferralSource.realtor,
    required this.createdAt,
  });

  factory Referral.fromJson(Map<String, dynamic> json) {
    return Referral(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      userId: json['user_id'] as String,
      source: ReferralSource.fromJson(json['source'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'partner_id': partnerId,
      'user_id': userId,
      'source': source.toJson(),
    };
  }

  Referral copyWith({
    String? id,
    String? partnerId,
    String? userId,
    ReferralSource? source,
    DateTime? createdAt,
  }) {
    return Referral(
      id: id ?? this.id,
      partnerId: partnerId ?? this.partnerId,
      userId: userId ?? this.userId,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'Referral(id: $id, partnerId: $partnerId, userId: $userId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Referral && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
