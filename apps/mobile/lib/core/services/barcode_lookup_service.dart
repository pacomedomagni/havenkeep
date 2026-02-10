import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_client/supabase_client.dart';

/// Looks up product information using a barcode via the
/// `lookup-barcode` Supabase Edge Function.
class BarcodeLookupService {
  final Ref _ref;

  BarcodeLookupService(this._ref);

  /// Look up product information for a barcode.
  ///
  /// Returns a [BarcodeLookupResult] with product data if found,
  /// or an empty result if no match was found.
  Future<BarcodeLookupResult> lookupBarcode(String barcode) async {
    try {
      final client = _ref.read(supabaseClientProvider);
      final response = await client.functions.invoke(
        'lookup-barcode',
        body: {'barcode': barcode},
      );

      if (response.status != 200) {
        throw Exception(
          'Barcode lookup failed with status ${response.status}',
        );
      }

      final data = response.data as Map<String, dynamic>;
      return BarcodeLookupResult.fromJson(data);
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
