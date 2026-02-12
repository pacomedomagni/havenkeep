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
      final data = await _client.get('/api/v1/documents',
          queryParams: {'itemId': itemId});

      final docs = data['documents'] as List;
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
      final data = await _client.get('/api/v1/documents');
      final docs = data['documents'] as List;
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
  Future<Document> uploadDocument({
    required String itemId,
    required String filePath,
    required String fileName,
    required DocumentType type,
    String? mimeType,
  }) async {
    try {
      final file = File(filePath);

      final data = await _client.upload(
        '/api/v1/documents/upload',
        file: file,
        fieldName: 'files',
        fields: {
          'itemId': itemId,
          'type': type.toJson(),
          if (mimeType != null) 'mimeType': mimeType,
        },
      );

      return Document.fromJson(data['document'] as Map<String, dynamic>);
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
      await _client.delete('/api/v1/documents/$documentId');
    } catch (e) {
      debugPrint('[DocumentsRepository] deleteDocument failed: $e');
      rethrow;
    }
  }
}
