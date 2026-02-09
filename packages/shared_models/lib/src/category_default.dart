import 'enums.dart';

/// Default settings for an item category (room, warranty, icon).
/// Populated from the category_defaults reference table.
class CategoryDefault {
  final ItemCategory category;
  final ItemRoom? defaultRoom;
  final int warrantyMonths;
  final String icon;

  const CategoryDefault({
    required this.category,
    this.defaultRoom,
    this.warrantyMonths = 12,
    this.icon = '\u{1F4E6}', // 📦
  });

  factory CategoryDefault.fromJson(Map<String, dynamic> json) {
    return CategoryDefault(
      category: ItemCategory.fromJson(json['category'] as String),
      defaultRoom: json['default_room'] != null
          ? ItemRoom.fromJson(json['default_room'] as String)
          : null,
      warrantyMonths: json['warranty_months'] as int? ?? 12,
      icon: json['icon'] as String? ?? '\u{1F4E6}',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category.toJson(),
      'default_room': defaultRoom?.toJson(),
      'warranty_months': warrantyMonths,
      'icon': icon,
    };
  }

  /// Warranty duration as a human-readable string.
  String get warrantyDurationLabel {
    if (warrantyMonths >= 12 && warrantyMonths % 12 == 0) {
      final years = warrantyMonths ~/ 12;
      return '$years ${years == 1 ? 'year' : 'years'}';
    }
    return '$warrantyMonths ${warrantyMonths == 1 ? 'month' : 'months'}';
  }

  CategoryDefault copyWith({
    ItemCategory? category,
    ItemRoom? defaultRoom,
    bool clearDefaultRoom = false,
    int? warrantyMonths,
    String? icon,
  }) {
    return CategoryDefault(
      category: category ?? this.category,
      defaultRoom:
          clearDefaultRoom ? null : (defaultRoom ?? this.defaultRoom),
      warrantyMonths: warrantyMonths ?? this.warrantyMonths,
      icon: icon ?? this.icon,
    );
  }

  @override
  String toString() =>
      'CategoryDefault(category: ${category.name}, warrantyMonths: $warrantyMonths)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryDefault && other.category == category;

  @override
  int get hashCode => category.hashCode;
}
