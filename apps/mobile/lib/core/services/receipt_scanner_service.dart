import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:api_client/api_client.dart';

/// Scans receipts using the Express API receipt scanning endpoint.
class ReceiptScannerService {
  final Ref _ref;

  ReceiptScannerService(this._ref);

  /// Scan a receipt image and return structured data.
  ///
  /// Encodes the image as base64 and sends it to the API.
  /// Returns a [ReceiptScanResult] with extracted fields.
  Future<ReceiptScanResult> scanReceipt(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final client = _ref.read(apiClientProvider);
      final response = await client.post(
        '/api/v1/receipts/scan',
        body: {'image': base64Image},
      );

      final data = response['data'] as Map<String, dynamic>? ?? response;
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
