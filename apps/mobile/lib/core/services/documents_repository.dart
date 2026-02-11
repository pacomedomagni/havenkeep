import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_client/supabase_client.dart';

/// Handles document uploads, fetching, and deletion via Supabase Storage.
class DocumentsRepository {
  final SupabaseClient _client;

  DocumentsRepository(this._client);

  // ============================================
  // READ
  // ============================================

  /// Get all documents for an item.
  Future<List<Document>> getDocumentsForItem(String itemId) async {
    try {
      final data = await _client
          .from(kDocumentsTable)
          .select()
          .eq('item_id', itemId)
          .order('created_at', ascending: false);

      return (data as List).map((json) => Document.fromJson(json)).toList();
    } on PostgrestException catch (e) {
      debugPrint('[DocumentsRepository] getDocumentsForItem failed: ${e.message}');
      rethrow;
    }
  }

  /// Get all documents for the current user.
  Future<List<Document>> getAllDocuments() async {
    try {
      final userId = requireCurrentUserId();

      final data = await _client
          .from(kDocumentsTable)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (data as List).map((json) => Document.fromJson(json)).toList();
    } on PostgrestException catch (e) {
      debugPrint('[DocumentsRepository] getAllDocuments failed: ${e.message}');
      rethrow;
    }
  }

  // ============================================
  // UPLOAD
  // ============================================

  /// Upload a document file and create a DB record.
  ///
  /// Storage path: documents/{userId}/{itemId}/{fileName}
  Future<Document> uploadDocument({
    required String itemId,
    required String filePath,
    required String fileName,
    required DocumentType type,
    String? mimeType,
  }) async {
    try {
      final userId = requireCurrentUserId();
      final file = File(filePath);
      final fileBytes = await file.readAsBytes();
      final storagePath = '$userId/$itemId/$fileName';

      // Upload to Supabase Storage
      await _client.storage
          .from(kDocumentsBucket)
          .uploadBinary(
            storagePath,
            fileBytes,
            fileOptions: FileOptions(
              contentType: mimeType ?? _inferMimeType(fileName),
            ),
          );

      // Get the file URL
      final fileUrl = _client.storage
          .from(kDocumentsBucket)
          .getPublicUrl(storagePath);

      // Create DB record
      final data = await _client.from(kDocumentsTable).insert({
        'item_id': itemId,
        'user_id': userId,
        'type': type.toJson(),
        'file_url': fileUrl,
        'file_name': fileName,
        'file_size': fileBytes.length,
        'mime_type': mimeType ?? _inferMimeType(fileName),
      }).select().single();

      return Document.fromJson(data);
    } on StorageException catch (e) {
      debugPrint('[DocumentsRepository] uploadDocument storage failed: ${e.message}');
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('[DocumentsRepository] uploadDocument DB failed: ${e.message}');
      rethrow;
    }
  }

  // ============================================
  // DELETE
  // ============================================

  /// Delete a document (both Storage file and DB record).
  Future<void> deleteDocument(String documentId) async {
    try {
      // Get the document to find the storage path
      final doc = await _client
          .from(kDocumentsTable)
          .select()
          .eq('id', documentId)
          .single();

      final document = Document.fromJson(doc);

      // Delete from Storage
      final storagePath =
          '${document.userId}/${document.itemId}/${document.fileName}';
      await _client.storage
          .from(kDocumentsBucket)
          .remove([storagePath]);

      // Delete DB record
      await _client
          .from(kDocumentsTable)
          .delete()
          .eq('id', documentId);
    } on StorageException catch (e) {
      debugPrint('[DocumentsRepository] deleteDocument storage failed: ${e.message}');
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('[DocumentsRepository] deleteDocument DB failed: ${e.message}');
      rethrow;
    }
  }

  // ============================================
  // SIGNED URLS
  // ============================================

  /// Get a signed URL for a private document (valid for 1 hour).
  Future<String> getSignedUrl(String storagePath) async {
    try {
      final url = await _client.storage
          .from(kDocumentsBucket)
          .createSignedUrl(storagePath, 3600);

      return url;
    } on StorageException catch (e) {
      debugPrint('[DocumentsRepository] getSignedUrl failed: ${e.message}');
      rethrow;
    }
  }

  // ============================================
  // HELPERS
  // ============================================

  /// Infer MIME type from file extension.
  String _inferMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
  }
}
