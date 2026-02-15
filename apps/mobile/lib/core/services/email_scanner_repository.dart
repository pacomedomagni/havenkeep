import 'package:flutter/foundation.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

/// Handles email scanning operations via the Express API.
class EmailScannerRepository {
  final ApiClient _client;

  EmailScannerRepository(this._client);

  /// Start a new email scan.
  Future<EmailScan> initiateScan({
    required String provider,
    required String accessToken,
    DateTime? dateRangeStart,
    DateTime? dateRangeEnd,
  }) async {
    try {
      final body = <String, dynamic>{
        'provider': provider,
        'access_token': accessToken,
      };
      if (dateRangeStart != null) {
        body['date_range_start'] = dateRangeStart.toIso8601String();
      }
      if (dateRangeEnd != null) {
        body['date_range_end'] = dateRangeEnd.toIso8601String();
      }

      final data = await _client.post('/api/v1/email-scanner/scan', body: body);
      final responseData = data['data'];
      if (responseData == null) {
        throw StateError('Email scan response missing "data" field');
      }
      return EmailScan.fromJson(responseData as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[EmailScannerRepository] initiateScan failed: $e');
      rethrow;
    }
  }

  /// Get scan history for the current user.
  Future<List<EmailScan>> getScans() async {
    try {
      final data = await _client.get('/api/v1/email-scanner/scans');
      final responseData = data['data'];
      if (responseData == null) {
        throw StateError('Email scans response missing "data" field');
      }
      final scans = (responseData as List)
          .map((json) => EmailScan.fromJson(json as Map<String, dynamic>))
          .toList();
      return scans;
    } catch (e) {
      debugPrint('[EmailScannerRepository] getScans failed: $e');
      rethrow;
    }
  }

  /// Get scan status by ID.
  Future<EmailScan> getScanById(String id) async {
    try {
      final data = await _client.get('/api/v1/email-scanner/scans/$id');
      final responseData = data['data'];
      if (responseData == null) {
        throw StateError('Email scan response missing "data" field for scan $id');
      }
      return EmailScan.fromJson(responseData as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[EmailScannerRepository] getScanById failed: $e');
      rethrow;
    }
  }
}
