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
  final double? outOfPocket;
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
    this.outOfPocket,
    this.status = ClaimStatus.pending,
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
      id: json['id'] as String,
      userId: json['user_id'] as String,
      itemId: json['item_id'] as String,
      claimDate: DateTime.tryParse(json['claim_date'] as String? ?? '') ?? DateTime.now(),
      issueDescription: json['issue_description'] as String?,
      repairDescription: json['repair_description'] as String?,
      repairCost: (json['repair_cost'] as num).toDouble(),
      amountSaved: (json['amount_saved'] as num).toDouble(),
      outOfPocket: json['out_of_pocket'] != null
          ? (json['out_of_pocket'] as num).toDouble()
          : null,
      status: ClaimStatus.fromJson(json['status'] as String? ?? 'pending'),
      filedWith: json['filed_with'] as String?,
      claimNumber: json['claim_number'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
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
        if (outOfPocket != null) 'out_of_pocket': outOfPocket,
        'status': status.toJson(),
        if (filedWith != null) 'filed_with': filedWith,
        if (claimNumber != null) 'claim_number': claimNumber,
        if (notes != null) 'notes': notes,
      };
}

/// Status of a warranty claim.
enum ClaimStatus {
  pending,
  in_progress,
  completed,
  denied;

  factory ClaimStatus.fromJson(String value) {
    return ClaimStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ClaimStatus.pending,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        ClaimStatus.pending => 'Pending',
        ClaimStatus.in_progress => 'In Progress',
        ClaimStatus.completed => 'Completed',
        ClaimStatus.denied => 'Denied',
      };
}
