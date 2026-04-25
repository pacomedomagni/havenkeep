import 'dart:convert';

import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'add_item_wizard_screen.dart';

/// Persistence helper for the multi-step add-item wizard so a partially-filled
/// form survives accidental dismissal, OS process kill, or a switch to another
/// app. Drafts older than 24 hours are silently discarded so we never restore
/// stale fields against a different user expectation (Ch05-F025).
class AddItemDraft {
  static const _key = 'add_item_wizard_draft_v1';
  static const _maxAge = Duration(hours: 24);

  /// Persist the current wizard state. We accept defaults as JSON-friendly
  /// primitives so the model stays decoupled from `SharedPreferences`.
  static Future<void> save(WizardData data) async {
    if (!_hasAnyContent(data)) {
      // Nothing user-entered yet; don't pollute prefs.
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'savedAt': DateTime.now().toIso8601String(),
      'name': data.name,
      'category': data.category?.name,
      'brand': data.brand,
      'purchaseDate': data.purchaseDate?.toIso8601String(),
      'warrantyMonths': data.warrantyMonths,
      'warrantyType': data.warrantyType?.name,
      'warrantyProvider': data.warrantyProvider,
      'price': data.price,
      'store': data.store,
      'room': data.room?.name,
      'modelNumber': data.modelNumber,
      'serialNumber': data.serialNumber,
      'notes': data.notes,
    });
    await prefs.setString(_key, payload);
  }

  /// Load the most recent wizard draft, returning `null` when there is no
  /// draft, the draft is malformed, or it is older than [_maxAge].
  static Future<WizardData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;

      final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '');
      if (savedAt == null) return null;
      if (DateTime.now().difference(savedAt) > _maxAge) {
        await clear();
        return null;
      }

      final data = WizardData()
        ..name = json['name'] as String?
        ..brand = json['brand'] as String?
        ..purchaseDate = DateTime.tryParse(json['purchaseDate'] as String? ?? '')
        ..warrantyMonths = json['warrantyMonths'] as int? ?? 12
        ..warrantyProvider = json['warrantyProvider'] as String?
        ..price = (json['price'] as num?)?.toDouble()
        ..store = json['store'] as String?
        ..modelNumber = json['modelNumber'] as String?
        ..serialNumber = json['serialNumber'] as String?
        ..notes = json['notes'] as String?;

      final category = json['category'] as String?;
      if (category != null) {
        try {
          data.category = ItemCategory.fromJson(category);
        } catch (_) {
          data.category = null;
        }
      }

      final warrantyType = json['warrantyType'] as String?;
      if (warrantyType != null) {
        try {
          data.warrantyType = WarrantyType.fromJson(warrantyType);
        } catch (_) {
          data.warrantyType = WarrantyType.manufacturer;
        }
      }

      final room = json['room'] as String?;
      if (room != null) {
        try {
          data.room = ItemRoom.fromJson(room);
        } catch (_) {
          data.room = null;
        }
      }

      return data;
    } catch (_) {
      // Malformed payload — wipe so it can't keep poisoning future loads.
      await clear();
      return null;
    }
  }

  /// Clear any persisted draft.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Whether the wizard has accumulated any user-entered content worth
  /// preserving. Used to gate both the autosave and the discard prompt.
  static bool isDirty(WizardData data) => _hasAnyContent(data);

  static bool _hasAnyContent(WizardData data) {
    return (data.name != null && data.name!.trim().isNotEmpty) ||
        data.category != null ||
        (data.brand != null && data.brand!.trim().isNotEmpty) ||
        data.purchaseDate != null ||
        data.price != null ||
        (data.store != null && data.store!.trim().isNotEmpty) ||
        data.room != null ||
        (data.modelNumber != null && data.modelNumber!.trim().isNotEmpty) ||
        (data.serialNumber != null && data.serialNumber!.trim().isNotEmpty) ||
        (data.notes != null && data.notes!.trim().isNotEmpty) ||
        (data.warrantyProvider != null &&
            data.warrantyProvider!.trim().isNotEmpty);
  }
}
