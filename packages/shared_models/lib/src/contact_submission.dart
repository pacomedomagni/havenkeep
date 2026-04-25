/// A message submitted via the marketing site contact form.
///
/// Mirrors the `contact_submissions` table (mig 019). The mobile app does
/// not consume this directly; it lives in shared_models so the admin
/// dashboard and any backfill tooling can share a single deserializer
/// (Ch08-ContactSubmission-D081).
class ContactSubmission {
  final String id;
  final String name;
  final String email;
  final String subject;
  final String message;

  /// Source IPv4/IPv6 captured at submit time. Surfaced as a string because
  /// the wire format is whatever Postgres `INET` casts to text.
  final String? ipAddress;

  final DateTime createdAt;

  const ContactSubmission({
    required this.id,
    required this.name,
    required this.email,
    required this.subject,
    required this.message,
    this.ipAddress,
    required this.createdAt,
  });

  factory ContactSubmission.fromJson(Map<String, dynamic> json) {
    return ContactSubmission(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      message: json['message'] as String? ?? '',
      ipAddress: json['ip_address'] as String?,
      createdAt: _parseDate(json['created_at'])!,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'subject': subject,
        'message': message,
        if (ipAddress != null) 'ip_address': ipAddress,
        'created_at': createdAt.toIso8601String(),
      };

  /// JSON for POSTing a new submission. Strips id + ip_address +
  /// created_at — the server captures those itself.
  Map<String, dynamic> toCreateJson() => {
        'name': name,
        'email': email,
        'subject': subject,
        'message': message,
      };

  @override
  String toString() => 'ContactSubmission(id: $id, subject: $subject)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactSubmission && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
