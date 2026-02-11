import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_client/supabase_client.dart';

/// Scans receipts using the `scan-receipt` Supabase Edge Function.
class ReceiptScannerService {
  final Ref _ref;

  ReceiptScannerService(this._ref);

  /// Scan a receipt image and return structured data.
  ///
  /// Encodes the image as base64 and sends it to the Edge Function.
  /// Returns a [ReceiptScanResult] with extracted fields.
  Future<ReceiptScanResult> scanReceipt(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final client = _ref.read(supabaseClientProvider);
      final response = await client.functions.invoke(
        'scan-receipt',
        body: {'image': base64Image},
      );

      if (response.status != 200) {
        throw Exception(
          'Receipt scan failed with status ${response.status}',
        );
      }

      if (response.data == null) {
        throw Exception('Empty response from receipt scanner');
      }
      final data = response.data as Map<String, dynamic>;
      return ReceiptScanResult.fromJson(data);
    } catch (e) {
      debugPrint('[ReceiptScanner] Scan failed: $e');
      rethrow;
    }
  }
}

/// Riverpod provider for the receipt scanner service.
final receiptScannerServiceProvider = Provider<ReceiptScannerService>((ref) {
  return ReceiptScannerService(ref);
});
