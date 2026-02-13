/// Represents an email scan job for receipt import.
class EmailScan {
  final String id;
  final String userId;
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
      id: json['id'] as String,
      userId: json['user_id'] as String,
      provider: json['provider'] as String,
      providerEmail: json['provider_email'] as String?,
      scanDate: DateTime.parse(json['scan_date'] as String),
      dateRangeStart: json['date_range_start'] != null
          ? DateTime.parse(json['date_range_start'] as String)
          : null,
      dateRangeEnd: json['date_range_end'] != null
          ? DateTime.parse(json['date_range_end'] as String)
          : null,
      emailsScanned: (json['emails_scanned'] as num?)?.toInt() ?? 0,
      receiptsFound: (json['receipts_found'] as num?)?.toInt() ?? 0,
      itemsImported: (json['items_imported'] as num?)?.toInt() ?? 0,
      status: EmailScanStatus.fromJson(json['status'] as String? ?? 'pending'),
      errorMessage: json['error_message'] as String?,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

enum EmailScanStatus {
  pending,
  scanning,
  completed,
  failed;

  factory EmailScanStatus.fromJson(String value) {
    return EmailScanStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => EmailScanStatus.pending,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        EmailScanStatus.pending => 'Pending',
        EmailScanStatus.scanning => 'Scanning',
        EmailScanStatus.completed => 'Completed',
        EmailScanStatus.failed => 'Failed',
      };
}
