import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_client/supabase_client.dart';

/// Handles reference data: category defaults and brand suggestions.
class CategoryRepository {
  final SupabaseClient _client;

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

    final data = await _client
        .from(kCategoryDefaultsTable)
        .select()
        .order('category', ascending: true);

    _cachedDefaults = (data as List)
        .map((json) => CategoryDefault.fromJson(json))
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

    final data = await _client
        .from(kBrandSuggestionsTable)
        .select()
        .eq('category', category.toJson())
        .order('sort_order', ascending: true);

    final brands = (data as List)
        .map((json) => BrandSuggestion.fromJson(json))
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
