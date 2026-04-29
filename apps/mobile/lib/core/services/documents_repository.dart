import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

/// Handles document uploads, fetching, and deletion via the Express API.
class DocumentsRepository {
  final ApiClient _client;

  DocumentsRepository(this._client);

  // ============================================
  // READ
  // ============================================

  /// Get all documents for an item.
  Future<List<Document>> getDocumentsForItem(String itemId) async {
    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'documents'],
        queryParams: {'item_id': itemId},
      );

      final docs = data['data'] as List;
      return docs
          .map((json) => Document.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[DocumentsRepository] getDocumentsForItem failed: $e');
      rethrow;
    }
  }

  /// Get all documents for the current user.
  Future<List<Document>> getAllDocuments() async {
    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'documents'],
      );
      final docs = data['data'] as List;
      return docs
          .map((json) => Document.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[DocumentsRepository] getAllDocuments failed: $e');
      rethrow;
    }
  }

  // ============================================
  // UPLOAD
  // ============================================

  /// Upload a document file and create a DB record.
  ///
  /// 2.12: `mime_type` is no longer sent. The server's
  /// `uploadDocumentSchema` is `.unknown(false)` and only declares
  /// `itemId` + `type`; the multer-detected mimetype + magic-byte check
  /// is what the server actually trusts. Sending it would either 400 in
  /// dev/staging or be silently stripped with a "Validator stripped
  /// unknown keys" log entry in prod.
  Future<Document> uploadDocument({
    required String itemId,
    required String filePath,
    required String fileName,
    required DocumentType type,
    String? idempotencyKey,
  }) async {
    try {
      final file = File(filePath);

      final data = await _client.upload(
        pathSegments: const ['api', 'v1', 'documents', 'upload'],
        file: file,
        fieldName: 'files',
        fields: {
          'item_id': itemId,
          'type': type.toJson(),
        },
        idempotencyKey: idempotencyKey,
      );

      return Document.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[DocumentsRepository] uploadDocument failed: $e');
      rethrow;
    }
  }

  // ============================================
  // DELETE
  // ============================================

  /// Delete a document (both storage file and DB record).
  Future<void> deleteDocument(String documentId) async {
    try {
      await _client.delete(
        pathSegments: ['api', 'v1', 'documents', documentId],
      );
    } catch (e) {
      debugPrint('[DocumentsRepository] deleteDocument failed: $e');
      rethrow;
    }
  }
}
