import 'package:flutter_test/flutter_test.dart';
import 'package:havenkeep_mobile/features/add_item/wizard/add_item_draft.dart';
import 'package:havenkeep_mobile/features/add_item/wizard/add_item_wizard_screen.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AddItemDraft.isDirty', () {
    test('is false on a freshly-constructed wizard data', () {
      final data = WizardData();
      expect(AddItemDraft.isDirty(data), isFalse);
    });

    test('is true once any text field has content', () {
      final data = WizardData()..name = 'Fridge';
      expect(AddItemDraft.isDirty(data), isTrue);
    });

    test('is false for whitespace-only text content', () {
      final data = WizardData()..name = '   ';
      expect(AddItemDraft.isDirty(data), isFalse);
    });

    test('is true once a category is picked', () {
      final data = WizardData()..category = ItemCategory.refrigerator;
      expect(AddItemDraft.isDirty(data), isTrue);
    });
  });

  group('AddItemDraft.save / load round-trip', () {
    test('returns null when nothing has been saved', () async {
      final restored = await AddItemDraft.load();
      expect(restored, isNull);
    });

    test('does not write a draft when wizard is empty', () async {
      final data = WizardData();
      await AddItemDraft.save(data);
      // Even after a save() call, isDirty=false drafts must not pollute prefs.
      final restored = await AddItemDraft.load();
      expect(restored, isNull);
    });

    test('round-trips every persisted field', () async {
      final saved = WizardData()
        ..name = 'Refrigerator'
        ..brand = 'Samsung'
        ..category = ItemCategory.refrigerator
        ..purchaseDate = DateTime(2024, 6, 15)
        ..warrantyMonths = 24
        ..warrantyType = WarrantyType.extended
        ..warrantyProvider = 'AppleCare+'
        ..price = 1299.99
        ..store = 'Best Buy'
        ..room = ItemRoom.kitchen
        ..modelNumber = 'RF28R7351SR'
        ..serialNumber = 'A1B2C3'
        ..notes = 'Top freezer';

      await AddItemDraft.save(saved);

      final restored = await AddItemDraft.load();
      expect(restored, isNotNull);
      expect(restored!.name, 'Refrigerator');
      expect(restored.brand, 'Samsung');
      expect(restored.category, ItemCategory.refrigerator);
      expect(restored.purchaseDate, DateTime(2024, 6, 15));
      expect(restored.warrantyMonths, 24);
      expect(restored.warrantyType, WarrantyType.extended);
      expect(restored.warrantyProvider, 'AppleCare+');
      expect(restored.price, 1299.99);
      expect(restored.store, 'Best Buy');
      expect(restored.room, ItemRoom.kitchen);
      expect(restored.modelNumber, 'RF28R7351SR');
      expect(restored.serialNumber, 'A1B2C3');
      expect(restored.notes, 'Top freezer');
    });

    test('clear() removes the persisted draft', () async {
      final data = WizardData()..name = 'Microwave';
      await AddItemDraft.save(data);
      expect(await AddItemDraft.load(), isNotNull);

      await AddItemDraft.clear();
      expect(await AddItemDraft.load(), isNull);
    });
  });

  group('AddItemDraft expiry', () {
    test('discards drafts older than 24 hours', () async {
      // Stage a stale payload directly in prefs. This bypasses save() so
      // we can simulate a draft that was written more than 24h ago.
      final stale = DateTime.now().subtract(const Duration(hours: 25));
      SharedPreferences.setMockInitialValues({
        'add_item_wizard_draft_v1':
            '{"savedAt":"${stale.toIso8601String()}","name":"Stale"}',
      });

      final restored = await AddItemDraft.load();
      expect(restored, isNull);
    });

    test('wipes corrupt drafts on load', () async {
      SharedPreferences.setMockInitialValues({
        'add_item_wizard_draft_v1': 'not valid json {',
      });
      final restored = await AddItemDraft.load();
      expect(restored, isNull);

      // Subsequent load returns null because the malformed payload was
      // wiped on first read.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('add_item_wizard_draft_v1'), isNull);
    });
  });
}
