import 'enums.dart';

/// A pre-populated brand suggestion for a given item category.
class BrandSuggestion {
  final String id;
  final ItemCategory category;
  final String brand;
  final int sortOrder;

  const BrandSuggestion({
    required this.id,
    required this.category,
    required this.brand,
    this.sortOrder = 0,
  });

  factory BrandSuggestion.fromJson(Map<String, dynamic> json) {
    return BrandSuggestion(
      id: json['id'] as String,
      category: ItemCategory.fromJson(json['category'] as String),
      brand: json['brand'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category.toJson(),
      'brand': brand,
      'sort_order': sortOrder,
    };
  }

  BrandSuggestion copyWith({
    String? id,
    ItemCategory? category,
    String? brand,
    int? sortOrder,
  }) {
    return BrandSuggestion(
      id: id ?? this.id,
      category: category ?? this.category,
      brand: brand ?? this.brand,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  String toString() => 'BrandSuggestion(brand: $brand, category: ${category.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BrandSuggestion && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
