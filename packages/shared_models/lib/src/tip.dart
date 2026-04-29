/// A dynamic tip surfaced in the home dashboard / notifications feed.
///
/// Mirrors the `tips` table (mig 018). Read-only on the client —
/// new tips are seeded by the API operator via SQL, never the app
/// (Ch08-Category-D088).
class Tip {
  final int id;

  /// Bucket the tip is filed under (`new_user`, `maintenance`, `warranty`,
  /// `general`, `organization`, `power_user`).
  final String category;

  /// Optional condition the API uses to decide when to serve this tip,
  /// e.g. `no_items` for `new_user` rows. Null for general-pool fallbacks.
  final String? triggerCondition;

  final String content;
  final bool isActive;
  final DateTime createdAt;

  const Tip({
    required this.id,
    required this.category,
    this.triggerCondition,
    required this.content,
    this.isActive = true,
    required this.createdAt,
  });

  factory Tip.fromJson(Map<String, dynamic> json) {
    return Tip(
      id: (json['id'] as num).toInt(),
      category: json['category'] as String? ?? 'general',
      triggerCondition: json['trigger_condition'] as String?,
      content: json['content'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      // 4.1: server-stamped timestamp falls back instead of crashing.
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        if (triggerCondition != null) 'trigger_condition': triggerCondition,
        'content': content,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
      };

  @override
  String toString() => 'Tip(id: $id, category: $category)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Tip && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
