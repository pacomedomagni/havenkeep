import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:api_client/api_client.dart';

/// Looks up product information using a barcode via the Express API.
class BarcodeLookupService {
  final Ref _ref;

  BarcodeLookupService(this._ref);

  /// Look up product information for a barcode.
  ///
  /// Returns a [BarcodeLookupResult] with product data if found,
  /// or an empty result if no match was found.
  Future<BarcodeLookupResult> lookupBarcode(String barcode) async {
    try {
      final client = _ref.read(apiClientProvider);
      final data = await client.post(
        '/api/v1/barcode/lookup',
        body: {'barcode': barcode},
      );

      return BarcodeLookupResult.fromJson(
          data['data'] as Map<String, dynamic>? ?? data);
    } catch (e) {
      debugPrint('[BarcodeLookup] Lookup failed: $e');
      // Return empty result instead of throwing
      return BarcodeLookupResult(barcode: barcode);
    }
  }
}

/// Riverpod provider for the barcode lookup service.
final barcodeLookupServiceProvider = Provider<BarcodeLookupService>((ref) {
  return BarcodeLookupService(ref);
});
