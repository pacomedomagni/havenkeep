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
  /// Streams the file as a multipart upload (field name `image`) so we
  /// don't have to base64-encode the entire payload into a JSON body —
  /// that pattern OOMs the device on larger photos and inflates the
  /// payload by ~33%.
  Future<ReceiptScanResult> scanReceipt(File imageFile) async {
    try {
      final client = _ref.read(apiClientProvider);
      final response = await client.upload(
        pathSegments: const ['api', 'v1', 'receipts', 'scan'],
        file: imageFile,
        fieldName: 'image',
      );

      final data = response['data'] as Map<String, dynamic>;
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
