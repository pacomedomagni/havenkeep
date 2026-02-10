import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('Item Model', () {
    group('computedWarrantyStatus', () {
      test('returns active for recently purchased item with 12 month warranty',
          () {
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 30)),
          warrantyMonths: 12,
        );

        expect(item.computedWarrantyStatus, WarrantyStatus.active);
      });

      test('returns expiring when within 90 days of expiration', () {
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 300)),
          warrantyMonths: 12,
        );

        expect(item.computedWarrantyStatus, WarrantyStatus.expiring);
      });

      test('returns expired for item past warranty period', () {
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 400)),
          warrantyMonths: 12,
        );

        expect(item.computedWarrantyStatus, WarrantyStatus.expired);
      });

      test('returns expiring on the 90th day before expiration', () {
        // Warranty expires in exactly 90 days
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 270)),
          warrantyMonths: 12,
        );

        expect(item.computedWarrantyStatus, WarrantyStatus.expiring);
      });

      test('returns expired on expiration day', () {
        // Warranty expires today
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 360)),
          warrantyMonths: 12,
        );

        expect(item.computedWarrantyStatus, WarrantyStatus.expired);
      });

      test('uses warrantyEndDate if provided (from database view)', () {
        final endDate = DateTime.now().add(const Duration(days: 10));
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 355)),
          warrantyMonths: 12,
          warrantyEndDate: endDate,
        );

        expect(item.computedWarrantyStatus, WarrantyStatus.expiring);
      });

      test('uses warrantyStatus if provided (from database view)', () {
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 30)),
          warrantyMonths: 12,
          status: WarrantyStatus.active,
        );

        expect(item.computedWarrantyStatus, WarrantyStatus.active);
      });

      test('handles long warranty periods correctly (5 years)', () {
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 30)),
          warrantyMonths: 60, // 5 years
        );

        expect(item.computedWarrantyStatus, WarrantyStatus.active);
      });

      test('handles very short warranty periods (1 month)', () {
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 35)),
          warrantyMonths: 1,
        );

        expect(item.computedWarrantyStatus, WarrantyStatus.expired);
      });
    });

    group('computedDaysRemaining', () {
      test('returns correct positive days remaining', () {
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 300)),
          warrantyMonths: 12,
        );

        // Should be approximately 60 days remaining
        expect(item.computedDaysRemaining, closeTo(60, 5));
      });

      test('returns negative days for expired warranty', () {
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 400)),
          warrantyMonths: 12,
        );

        expect(item.computedDaysRemaining, lessThan(0));
      });

      test('returns 0 on expiration day', () {
        // Warranty expires in ~0 days
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 360)),
          warrantyMonths: 12,
        );

        expect(item.computedDaysRemaining, closeTo(0, 2));
      });

      test('uses daysRemaining if provided (from database view)', () {
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now(),
          warrantyMonths: 12,
          daysRemaining: 42,
        );

        expect(item.computedDaysRemaining, 42);
      });

      test('calculates correctly for long warranties', () {
        final item = TestHelpers.createTestItem(
          purchaseDate: DateTime.now().subtract(const Duration(days: 30)),
          warrantyMonths: 60, // 5 years
        );

        // Should have ~1770 days remaining (5 years - 30 days)
        expect(item.computedDaysRemaining, greaterThan(1700));
      });
    });

    group('fromJson / toJson', () {
      test('round-trip serialization preserves all fields', () {
        final now = DateTime.now();
        final item = TestHelpers.createTestItem(
          id: 'test-id',
          name: 'Test Refrigerator',
          brand: 'Samsung',
          modelNumber: 'RF28R7351SR',
          serialNumber: 'ABC123456',
          category: ItemCategory.refrigerator,
          room: ItemRoom.kitchen,
          purchaseDate: DateTime(2023, 1, 15),
          store: 'Home Depot',
          price: 2499.99,
          warrantyMonths: 12,
          warrantyType: WarrantyType.manufacturer,
          notes: 'Delivered on 1/20/23',
          isArchived: false,
        );

        final json = item.toJson();
        final deserialized = Item.fromJson(json);

        expect(deserialized.id, item.id);
        expect(deserialized.name, item.name);
        expect(deserialized.brand, item.brand);
        expect(deserialized.modelNumber, item.modelNumber);
        expect(deserialized.serialNumber, item.serialNumber);
        expect(deserialized.category, item.category);
        expect(deserialized.room, item.room);
        expect(deserialized.store, item.store);
        expect(deserialized.price, item.price);
        expect(deserialized.warrantyMonths, item.warrantyMonths);
        expect(deserialized.warrantyType, item.warrantyType);
        expect(deserialized.notes, item.notes);
        expect(deserialized.isArchived, item.isArchived);
      });

      test('handles null optional fields correctly', () {
        final item = TestHelpers.createTestItem(
          brand: null,
          modelNumber: null,
          serialNumber: null,
          room: null,
          store: null,
          price: null,
          notes: null,
        );

        final json = item.toJson();
        final deserialized = Item.fromJson(json);

        expect(deserialized.brand, isNull);
        expect(deserialized.modelNumber, isNull);
        expect(deserialized.serialNumber, isNull);
        expect(deserialized.room, isNull);
        expect(deserialized.store, isNull);
        expect(deserialized.price, isNull);
        expect(deserialized.notes, isNull);
      });

      test('toInsertJson excludes id', () {
        final item = TestHelpers.createTestItem(id: 'should-be-removed');

        final json = item.toInsertJson();

        expect(json.containsKey('id'), isFalse);
        expect(json.containsKey('name'), isTrue);
        expect(json.containsKey('purchase_date'), isTrue);
      });

      test('date fields serialize correctly', () {
        final purchaseDate = DateTime(2023, 1, 15);
        final item = TestHelpers.createTestItem(purchaseDate: purchaseDate);

        final json = item.toJson();

        expect(json['purchase_date'], '2023-01-15');
      });

      test('handles warrantyEndDate from database', () {
        final endDate = DateTime(2024, 1, 15);
        final json = {
          'id': 'test-id',
          'home_id': 'home-id',
          'user_id': 'user-id',
          'name': 'Test Item',
          'category': 'refrigerator',
          'purchase_date': '2023-01-15',
          'warranty_months': 12,
          'warranty_end_date': '2024-01-15',
          'warranty_type': 'manufacturer',
          'is_archived': false,
          'added_via': 'manual',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };

        final item = Item.fromJson(json);

        expect(item.warrantyEndDate, isNotNull);
        expect(item.warrantyEndDate!.year, 2024);
        expect(item.warrantyEndDate!.month, 1);
        expect(item.warrantyEndDate!.day, 15);
      });
    });

    group('copyWith', () {
      test('creates new instance with updated fields', () {
        final original = TestHelpers.createTestItem(
          name: 'Original Name',
          brand: 'Original Brand',
          price: 100.0,
        );

        final updated = original.copyWith(
          name: 'Updated Name',
          price: 200.0,
        );

        expect(updated.name, 'Updated Name');
        expect(updated.brand, 'Original Brand'); // Unchanged
        expect(updated.price, 200.0);
        expect(updated.id, original.id); // Same ID
      });

      test('clears optional fields with clear flags', () {
        final original = TestHelpers.createTestItem(
          brand: 'Samsung',
          notes: 'Some notes',
        );

        final updated = original.copyWith(
          clearBrand: true,
          clearNotes: true,
        );

        expect(updated.brand, isNull);
        expect(updated.notes, isNull);
      });

      test('does not modify original instance', () {
        final original = TestHelpers.createTestItem(name: 'Original');

        final updated = original.copyWith(name: 'Updated');

        expect(original.name, 'Original');
        expect(updated.name, 'Updated');
      });
    });

    group('equality and hashCode', () {
      test('items with same ID are equal', () {
        final item1 = TestHelpers.createTestItem(id: 'same-id');
        final item2 = TestHelpers.createTestItem(id: 'same-id');

        expect(item1, equals(item2));
        expect(item1.hashCode, equals(item2.hashCode));
      });

      test('items with different IDs are not equal', () {
        final item1 = TestHelpers.createTestItem(id: 'id-1');
        final item2 = TestHelpers.createTestItem(id: 'id-2');

        expect(item1, isNot(equals(item2)));
      });
    });
  });
}
