/// Result from barcode product lookup.
///
/// Represents the product data returned by the `lookup-barcode` Edge Function
/// after querying external product databases.
class BarcodeLookupResult {
  final String barcode;
  final String? brand;
  final String? productName;
  final String? category;
  final String? description;
  final String? imageUrl;

  const BarcodeLookupResult({
    required this.barcode,
    this.brand,
    this.productName,
    this.category,
    this.description,
    this.imageUrl,
  });

  factory BarcodeLookupResult.fromJson(Map<String, dynamic> json) {
    return BarcodeLookupResult(
      barcode: json['barcode'] as String,
      brand: json['brand'] as String?,
      productName: json['product_name'] as String?,
      category: json['category'] as String?,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'barcode': barcode,
      'brand': brand,
      'product_name': productName,
      'category': category,
      'description': description,
      'image_url': imageUrl,
    };
  }

  /// Whether the lookup returned any useful product data.
  bool get hasData => brand != null || productName != null;

  @override
  String toString() =>
      'BarcodeLookupResult(barcode: $barcode, brand: $brand, product: $productName)';
}
