import 'enums.dart';

/// A pre-populated brand suggestion for a given item category.
///
/// `brand` is bound to 255 chars on the API (`VARCHAR(255)`); the docstring
/// records the cap so callers don't ship longer values that the server will
/// truncate (Ch08-Category-D087).
class BrandSuggestion {
  final String id;
  final ItemCategory category;

  /// Brand name. Max length 255 chars (mirrors `brand_suggestions.brand`
  /// VARCHAR(255) on the server).
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
      id: json['id'] as String? ?? '',
      category: json['category'] != null
          ? ItemCategory.fromJson(json['category'] as String)
          : ItemCategory.other,
      brand: json['brand'] as String? ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
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
