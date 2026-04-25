import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/category_repository.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

import 'category_repository_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  late MockApiClient mockClient;
  late CategoryRepository repository;

  setUp(() {
    mockClient = MockApiClient();
    repository = CategoryRepository(mockClient);
  });

  /// Helper to build a valid category default JSON.
  Map<String, dynamic> categoryDefaultJson({
    String category = 'refrigerator',
    String? defaultRoom = 'kitchen',
    int warrantyMonths = 12,
    String icon = '🧊',
  }) {
    return {
      'category': category,
      'default_room': defaultRoom,
      'warranty_months': warrantyMonths,
      'icon': icon,
    };
  }

  /// Helper to build a valid brand suggestion JSON.
  Map<String, dynamic> brandSuggestionJson({
    String id = 'brand-1',
    String category = 'refrigerator',
    String brand = 'Samsung',
    int sortOrder = 0,
  }) {
    return {
      'id': id,
      'category': category,
      'brand': brand,
      'sort_order': sortOrder,
    };
  }

  group('CategoryRepository', () {
    group('getCategoryDefaults', () {
      test('calls correct endpoint and returns parsed data', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'defaults']))
            .thenAnswer((_) async => {
                  'data': [
                    categoryDefaultJson(category: 'refrigerator'),
                    categoryDefaultJson(
                        category: 'washer', defaultRoom: 'laundry'),
                  ],
                });

        final defaults = await repository.getCategoryDefaults();

        expect(defaults, hasLength(2));
        expect(defaults[0].category, ItemCategory.refrigerator);
        verify(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'defaults'])).called(1);
      });

      test('uses in-memory cache on second call', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'defaults']))
            .thenAnswer((_) async => {
                  'data': [
                    categoryDefaultJson(category: 'refrigerator'),
                  ],
                });

        // First call: hits API
        final first = await repository.getCategoryDefaults();
        // Second call: should use cache
        final second = await repository.getCategoryDefaults();

        expect(first, hasLength(1));
        expect(second, hasLength(1));
        // API should only be called once despite two getCategoryDefaults calls
        verify(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'defaults'])).called(1);
      });

      test('rethrows errors from API client', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'defaults']))
            .thenThrow(ApiException(500, 'Server error'));

        expect(
          () => repository.getCategoryDefaults(),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getBrandSuggestions', () {
      test('calls correct endpoint with category in path', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'refrigerator', 'brands']))
            .thenAnswer((_) async => {
                  'data': [
                    brandSuggestionJson(
                        id: 'b-1',
                        category: 'refrigerator',
                        brand: 'Samsung'),
                    brandSuggestionJson(
                        id: 'b-2', category: 'refrigerator', brand: 'LG'),
                  ],
                });

        final brands =
            await repository.getBrandSuggestions(ItemCategory.refrigerator);

        expect(brands, hasLength(2));
        expect(brands[0].brand, 'Samsung');
        expect(brands[1].brand, 'LG');
        verify(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'refrigerator', 'brands']))
            .called(1);
      });

      test('caches brand suggestions per category', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'refrigerator', 'brands']))
            .thenAnswer((_) async => {
                  'data': [
                    brandSuggestionJson(
                        id: 'b-1',
                        category: 'refrigerator',
                        brand: 'Samsung'),
                  ],
                });

        // First call: hits API
        final first =
            await repository.getBrandSuggestions(ItemCategory.refrigerator);
        // Second call: should use cache
        final second =
            await repository.getBrandSuggestions(ItemCategory.refrigerator);

        expect(first, hasLength(1));
        expect(second, hasLength(1));
        // API should only be called once due to caching
        verify(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'refrigerator', 'brands']))
            .called(1);
      });

      test('fetches separately for different categories', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'refrigerator', 'brands']))
            .thenAnswer((_) async => {
                  'data': [
                    brandSuggestionJson(
                        id: 'b-1',
                        category: 'refrigerator',
                        brand: 'Samsung'),
                  ],
                });
        when(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'washer', 'brands']))
            .thenAnswer((_) async => {
                  'data': [
                    brandSuggestionJson(
                        id: 'b-2', category: 'washer', brand: 'Whirlpool'),
                    brandSuggestionJson(
                        id: 'b-3', category: 'washer', brand: 'Maytag'),
                  ],
                });

        final fridgeBrands =
            await repository.getBrandSuggestions(ItemCategory.refrigerator);
        final washerBrands =
            await repository.getBrandSuggestions(ItemCategory.washer);

        expect(fridgeBrands, hasLength(1));
        expect(washerBrands, hasLength(2));
      });
    });

    group('clearCache', () {
      test('forces re-fetch of category defaults after clear', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'defaults']))
            .thenAnswer((_) async => {
                  'data': [
                    categoryDefaultJson(category: 'refrigerator'),
                  ],
                });

        // First call: populates cache
        await repository.getCategoryDefaults();

        // Clear cache
        repository.clearCache();

        // Second call: should hit API again
        await repository.getCategoryDefaults();

        verify(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'defaults'])).called(2);
      });

      test('forces re-fetch of brand suggestions after clear', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'refrigerator', 'brands']))
            .thenAnswer((_) async => {
                  'data': [
                    brandSuggestionJson(
                        id: 'b-1',
                        category: 'refrigerator',
                        brand: 'Samsung'),
                  ],
                });

        // First call: populates cache
        await repository.getBrandSuggestions(ItemCategory.refrigerator);

        // Clear cache
        repository.clearCache();

        // Second call: should hit API again
        await repository.getBrandSuggestions(ItemCategory.refrigerator);

        verify(mockClient.get(pathSegments: const ['api', 'v1', 'categories', 'refrigerator', 'brands']))
            .called(2);
      });
    });
  });
}
