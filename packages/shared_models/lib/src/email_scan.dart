/// Represents an email scan job for receipt import.
class EmailScan {
  final String id;
  final String userId;

  /// 'gmail' or 'outlook' (Ch08-EmailScan-D070 — DB CHECK enforces these).
  final String provider;

  final String? providerEmail;
  final DateTime scanDate;
  final DateTime? dateRangeStart;
  final DateTime? dateRangeEnd;
  final int emailsScanned;
  final int receiptsFound;
  final int itemsImported;
  final EmailScanStatus status;
  final String? errorMessage;
  final DateTime? completedAt;
  final DateTime createdAt;

  const EmailScan({
    required this.id,
    required this.userId,
    required this.provider,
    this.providerEmail,
    required this.scanDate,
    this.dateRangeStart,
    this.dateRangeEnd,
    required this.emailsScanned,
    required this.receiptsFound,
    required this.itemsImported,
    required this.status,
    this.errorMessage,
    this.completedAt,
    required this.createdAt,
  });

  factory EmailScan.fromJson(Map<String, dynamic> json) {
    return EmailScan(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      providerEmail: json['provider_email'] as String?,
      scanDate: _parseDate(json['scan_date'])!,
      dateRangeStart: _parseDate(json['date_range_start']),
      dateRangeEnd: _parseDate(json['date_range_end']),
      // Ch08-EmailScan-D069: counts arrive as JSON numbers (Postgres INTEGER).
      // The previous int.tryParse(.toString()) round-trip was masking type
      // bugs — now we trust the wire type and treat absent as 0.
      emailsScanned: (json['emails_scanned'] as num?)?.toInt() ?? 0,
      receiptsFound: (json['receipts_found'] as num?)?.toInt() ?? 0,
      itemsImported: (json['items_imported'] as num?)?.toInt() ?? 0,
      status: EmailScanStatus.fromJson(json['status'] as String? ?? 'pending'),
      errorMessage: json['error_message'] as String?,
      completedAt: _parseDate(json['completed_at']),
      createdAt: _parseDate(json['created_at'])!,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'provider': provider,
        if (providerEmail != null) 'provider_email': providerEmail,
        'scan_date': scanDate.toIso8601String(),
        if (dateRangeStart != null)
          'date_range_start': dateRangeStart!.toIso8601String().split('T').first,
        if (dateRangeEnd != null)
          'date_range_end': dateRangeEnd!.toIso8601String().split('T').first,
        'emails_scanned': emailsScanned,
        'receipts_found': receiptsFound,
        'items_imported': itemsImported,
        'status': status.toJson(),
        if (errorMessage != null) 'error_message': errorMessage,
        if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}

enum EmailScanStatus {
  pending,
  scanning,
  completed,
  failed;

  static const Map<String, EmailScanStatus> _byName = {
    'pending': EmailScanStatus.pending,
    'scanning': EmailScanStatus.scanning,
    'completed': EmailScanStatus.completed,
    'failed': EmailScanStatus.failed,
  };

  factory EmailScanStatus.fromJson(String value) {
    return _byName[value] ?? EmailScanStatus.pending;
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        EmailScanStatus.pending => 'Pending',
        EmailScanStatus.scanning => 'Scanning',
        EmailScanStatus.completed => 'Completed',
        EmailScanStatus.failed => 'Failed',
      };
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
