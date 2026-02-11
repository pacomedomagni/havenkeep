import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

/// Handles reference data: category defaults and brand suggestions via the Express API.
class CategoryRepository {
  final ApiClient _client;

  // Local cache (reference data doesn't change often)
  List<CategoryDefault>? _cachedDefaults;
  final Map<ItemCategory, List<BrandSuggestion>> _cachedBrands = {};

  CategoryRepository(this._client);

  // ============================================
  // CATEGORY DEFAULTS
  // ============================================

  /// Get all category defaults (cached after first fetch).
  Future<List<CategoryDefault>> getCategoryDefaults() async {
    if (_cachedDefaults != null) return _cachedDefaults!;

    final data = await _client.get('/api/v1/categories/defaults');
    final defaults = data['data'] as List;

    _cachedDefaults = defaults
        .map((json) => CategoryDefault.fromJson(json as Map<String, dynamic>))
        .toList();

    return _cachedDefaults!;
  }

  /// Get defaults for a specific category.
  Future<CategoryDefault?> getCategoryDefault(ItemCategory category) async {
    final defaults = await getCategoryDefaults();
    try {
      return defaults.firstWhere((d) => d.category == category);
    } catch (_) {
      return null;
    }
  }

  // ============================================
  // BRAND SUGGESTIONS
  // ============================================

  /// Get brand suggestions for a category (cached after first fetch per category).
  Future<List<BrandSuggestion>> getBrandSuggestions(
    ItemCategory category,
  ) async {
    if (_cachedBrands.containsKey(category)) {
      return _cachedBrands[category]!;
    }

    final data = await _client.get(
      '/api/v1/categories/${category.toJson()}/brands',
    );
    final brandsData = data['data'] as List;

    final brands = brandsData
        .map((json) => BrandSuggestion.fromJson(json as Map<String, dynamic>))
        .toList();

    _cachedBrands[category] = brands;
    return brands;
  }

  /// Get just the brand names for a category (convenience method).
  Future<List<String>> getBrandNames(ItemCategory category) async {
    final suggestions = await getBrandSuggestions(category);
    return suggestions.map((s) => s.brand).toList();
  }

  // ============================================
  // CACHE
  // ============================================

  /// Clear the local cache (e.g., on sign out).
  void clearCache() {
    _cachedDefaults = null;
    _cachedBrands.clear();
  }
}
