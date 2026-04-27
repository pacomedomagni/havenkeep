import '_unknown_enum_log.dart';

/// A warranty claim filed against an item.
class WarrantyClaim {
  final String id;
  final String userId;
  final String itemId;
  final DateTime claimDate;
  final String? issueDescription;
  final String? repairDescription;
  final double repairCost;
  final double amountSaved;

  /// `out_of_pocket` is `NUMERIC NOT NULL DEFAULT 0` on the API
  /// (Ch08-WarrantyClaim-D023). Always populated; defaults to 0 for legacy
  /// rows that pre-date the column.
  final double outOfPocket;

  final ClaimStatus status;
  final String? filedWith;
  final String? claimNumber;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined fields (from API)
  final String? itemName;
  final String? itemBrand;

  const WarrantyClaim({
    required this.id,
    required this.userId,
    required this.itemId,
    required this.claimDate,
    this.issueDescription,
    this.repairDescription,
    required this.repairCost,
    required this.amountSaved,
    this.outOfPocket = 0,
    this.status = ClaimStatus.filed,
    this.filedWith,
    this.claimNumber,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.itemName,
    this.itemBrand,
  });

  factory WarrantyClaim.fromJson(Map<String, dynamic> json) {
    return WarrantyClaim(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      itemId: json['item_id'] as String? ?? '',
      // Ch08-WarrantyClaim-D025: NO DateTime.now() fallback. The API never
      // returns a row without claim_date set; if it's absent the row is
      // garbage and we'd rather throw than invent a date.
      claimDate: _parseDate(json['claim_date'])!,
      issueDescription: json['issue_description'] as String?,
      repairDescription: json['repair_description'] as String?,
      repairCost: (json['repair_cost'] as num?)?.toDouble() ?? 0,
      amountSaved: (json['amount_saved'] as num?)?.toDouble() ?? 0,
      outOfPocket: (json['out_of_pocket'] as num?)?.toDouble() ?? 0,
      status: ClaimStatus.fromJson(json['status'] as String? ?? 'filed'),
      filedWith: json['filed_with'] as String?,
      claimNumber: json['claim_number'] as String?,
      notes: json['notes'] as String?,
      createdAt: _parseDate(json['created_at'])!,
      updatedAt: _parseDate(json['updated_at'])!,
      itemName: json['item_name'] as String?,
      itemBrand: json['item_brand'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'item_id': itemId,
        'claim_date': claimDate.toIso8601String(),
        'issue_description': issueDescription,
        'repair_description': repairDescription,
        'repair_cost': repairCost,
        'amount_saved': amountSaved,
        'out_of_pocket': outOfPocket,
        'status': status.toJson(),
        'filed_with': filedWith,
        'claim_number': claimNumber,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// JSON for creating a new claim (POST body).
  Map<String, dynamic> toCreateJson() => {
        'item_id': itemId,
        'claim_date': claimDate.toIso8601String(),
        if (issueDescription != null) 'issue_description': issueDescription,
        if (repairDescription != null) 'repair_description': repairDescription,
        'repair_cost': repairCost,
        'amount_saved': amountSaved,
        'out_of_pocket': outOfPocket,
        'status': status.toJson(),
        if (filedWith != null) 'filed_with': filedWith,
        if (claimNumber != null) 'claim_number': claimNumber,
        if (notes != null) 'notes': notes,
      };
}

/// Status of a warranty claim. Wire format is snake_case to match the
/// Postgres `claim_status` constraint set by migration 060
/// (Ch08-WarrantyClaim-D024): `filed | in_review | approved | denied |
/// settled | closed`.
enum ClaimStatus {
  filed,
  inReview,
  approved,
  denied,
  settled,
  closed;

  static const Map<String, ClaimStatus> _byName = {
    'filed': ClaimStatus.filed,
    'in_review': ClaimStatus.inReview,
    'approved': ClaimStatus.approved,
    'denied': ClaimStatus.denied,
    'settled': ClaimStatus.settled,
    'closed': ClaimStatus.closed,
  };

  factory ClaimStatus.fromJson(String value) {
    final mapped = _byName[value];
    if (mapped != null) return mapped;
    // Unknown value: log via the shared funnel (Ch08-D018) so an enum drift
    // between server and client surfaces in platform logs (and any custom
    // reporter the bootstrap registers), then coerce to `filed` so the UI
    // keeps rendering.
    logUnknownEnumValue(
      enumName: 'ClaimStatus',
      unknownValue: value,
      fallback: 'filed',
    );
    return ClaimStatus.filed;
  }

  String toJson() => switch (this) {
        ClaimStatus.inReview => 'in_review',
        _ => name,
      };

  String get displayLabel => switch (this) {
        ClaimStatus.filed => 'Filed',
        ClaimStatus.inReview => 'In Review',
        ClaimStatus.approved => 'Approved',
        ClaimStatus.denied => 'Denied',
        ClaimStatus.settled => 'Settled',
        ClaimStatus.closed => 'Closed',
      };
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
