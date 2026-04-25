import 'package:flutter/foundation.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

/// Handles email scanning operations via the Express API.
class EmailScannerRepository {
  final ApiClient _client;

  EmailScannerRepository(this._client);

  /// Start a new email scan. The mobile client forwards the OAuth `code` +
  /// `redirectUri` to the API, which exchanges them server-side for an
  /// access + refresh token. The mobile client never holds an access token.
  Future<EmailScan> initiateScan({
    required String provider,
    required String code,
    required String redirectUri,
    DateTime? dateRangeStart,
    DateTime? dateRangeEnd,
  }) async {
    try {
      final body = <String, dynamic>{
        'provider': provider,
        'code': code,
        'redirect_uri': redirectUri,
      };
      if (dateRangeStart != null) {
        body['date_range_start'] = dateRangeStart.toIso8601String();
      }
      if (dateRangeEnd != null) {
        body['date_range_end'] = dateRangeEnd.toIso8601String();
      }

      final data = await _client.post(
        pathSegments: const ['api', 'v1', 'email-scanner', 'scan'],
        body: body,
      );
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
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'email-scanner', 'scans'],
      );
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
      final data = await _client.get(
        pathSegments: ['api', 'v1', 'email-scanner', 'scans', id],
      );
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

  /// Cancel an in-flight scan. Server flips it to `failed` with a
  /// "Cancelled by user" message so the polling loop terminates and the
  /// progress dialog can dismiss.
  Future<EmailScan> cancelScan(String id) async {
    try {
      final data = await _client.post(
        pathSegments: ['api', 'v1', 'email-scanner', 'scans', id, 'cancel'],
        body: const <String, dynamic>{},
      );
      final responseData = data['data'];
      if (responseData == null) {
        throw StateError('Cancel-scan response missing "data" field for scan $id');
      }
      return EmailScan.fromJson(responseData as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[EmailScannerRepository] cancelScan failed: $e');
      rethrow;
    }
  }

  /// List the user's active OAuth integrations. Used for the granted-scopes
  /// chips and the in-app disconnect entry in settings.
  Future<List<EmailIntegration>> listIntegrations() async {
    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'email-scanner', 'integrations'],
      );
      final list = (data['data'] as List?) ?? const [];
      return list
          .map((json) => EmailIntegration.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[EmailScannerRepository] listIntegrations failed: $e');
      rethrow;
    }
  }

  /// Revoke a single provider integration (or all when [provider] is null).
  Future<void> revokeIntegration({String? provider}) async {
    try {
      await _client.delete(
        pathSegments: const ['api', 'v1', 'email-scanner', 'integrations'],
        queryParams: provider != null ? {'provider': provider} : null,
      );
    } catch (e) {
      debugPrint('[EmailScannerRepository] revokeIntegration failed: $e');
      rethrow;
    }
  }

  /// List pending review-queue rows.
  Future<List<EmailReviewQueueEntry>> listPendingReviews() async {
    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'email-scanner', 'review'],
      );
      final list = (data['data'] as List?) ?? const [];
      return list
          .map((json) =>
              EmailReviewQueueEntry.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[EmailScannerRepository] listPendingReviews failed: $e');
      rethrow;
    }
  }

  /// Approve a review-queue row. Server creates the underlying item and
  /// returns the created item id.
  Future<String> approveReview(String id) async {
    try {
      final data = await _client.post(
        pathSegments: ['api', 'v1', 'email-scanner', 'review', id, 'approve'],
        body: const <String, dynamic>{},
      );
      final result = data['data'] as Map<String, dynamic>?;
      final itemId = result?['item_id'] as String?;
      if (itemId == null) {
        throw StateError('Approve-review response missing "item_id"');
      }
      return itemId;
    } catch (e) {
      debugPrint('[EmailScannerRepository] approveReview failed: $e');
      rethrow;
    }
  }

  /// Reject a review-queue row. Optional [reason] is surfaced in audit logs.
  Future<void> rejectReview(String id, {String? reason}) async {
    try {
      await _client.post(
        pathSegments: ['api', 'v1', 'email-scanner', 'review', id, 'reject'],
        body: reason != null ? {'reason': reason} : const <String, dynamic>{},
      );
    } catch (e) {
      debugPrint('[EmailScannerRepository] rejectReview failed: $e');
      rethrow;
    }
  }
}

/// One row of the user's `user_oauth_integrations` table, as returned by
/// `GET /api/v1/email-scanner/integrations`. Strips the encrypted token
/// blobs since clients never need them.
class EmailIntegration {
  final String id;
  final String provider;
  final String providerEmail;
  final List<String> grantedScopes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? accessTokenExpiresAt;

  const EmailIntegration({
    required this.id,
    required this.provider,
    required this.providerEmail,
    required this.grantedScopes,
    required this.createdAt,
    required this.updatedAt,
    this.accessTokenExpiresAt,
  });

  factory EmailIntegration.fromJson(Map<String, dynamic> json) {
    final scope = (json['granted_scope'] as String? ?? '').trim();
    return EmailIntegration(
      id: json['id'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      providerEmail: json['provider_email'] as String? ?? '',
      grantedScopes: scope.isEmpty
          ? const <String>[]
          : scope.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      accessTokenExpiresAt:
          DateTime.tryParse(json['access_token_expires_at'] as String? ?? ''),
    );
  }
}

/// One row of the email scanner review queue. `suggestedItem` is the raw
/// JSON the AI extracted; the UI renders the relevant fields for the
/// human reviewer to confirm.
class EmailReviewQueueEntry {
  final String id;
  final String emailScanId;
  final String senderAddress;
  final String senderDomain;
  final String? subject;
  final Map<String, dynamic> suggestedItem;
  final double confidenceScore;
  final DateTime createdAt;

  const EmailReviewQueueEntry({
    required this.id,
    required this.emailScanId,
    required this.senderAddress,
    required this.senderDomain,
    required this.subject,
    required this.suggestedItem,
    required this.confidenceScore,
    required this.createdAt,
  });

  String get suggestedName =>
      (suggestedItem['productName'] as String?)?.trim().isNotEmpty == true
          ? suggestedItem['productName'] as String
          : (subject ?? 'Suggested item');

  String? get suggestedBrand => suggestedItem['brand'] as String?;

  factory EmailReviewQueueEntry.fromJson(Map<String, dynamic> json) {
    final rawConf = json['confidence_score'];
    final confidence = rawConf is num
        ? rawConf.toDouble()
        : double.tryParse(rawConf?.toString() ?? '') ?? 0;
    return EmailReviewQueueEntry(
      id: json['id'] as String? ?? '',
      emailScanId: json['email_scan_id'] as String? ?? '',
      senderAddress: json['sender_address'] as String? ?? '',
      senderDomain: json['sender_domain'] as String? ?? '',
      subject: json['subject'] as String?,
      suggestedItem: (json['suggested_item'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
      confidenceScore: confidence.clamp(0, 1).toDouble(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
